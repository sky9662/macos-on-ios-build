"""Read-only JIT ABI audit; emits counts, not game code or instructions."""
import argparse
from collections import Counter
import hashlib
import json
import pathlib
import re
import shutil
import subprocess
import sys

BINARIES = ("Turing Complete", "compile.dylib")
ENTRY_POINTS = ("_c_get_memory", "_c_get_persistent_memory", "_c_set_protection", "_c_jit", "_c_free_memory")
SYSTEM_CALLS = ("_mmap", "_pthread_jit_write_protect_np", "_sys_icache_invalidate", "_munmap")
LABEL = re.compile(r"^\s*(_[A-Za-z0-9_.$]+):\s*$")
BRANCH = re.compile(r"\b(?:bl|b)\s+([^\s;]+)(?:\s*;\s*symbol stub for:\s*(_\w+))?")


def summarize(disassembly):
    definitions = set()
    direct = {name: 0 for name in ENTRY_POINTS}
    wrappers = {name: {symbol: 0 for symbol in SYSTEM_CALLS} for name in ENTRY_POINTS}
    current = None
    for line in disassembly.splitlines():
        label = LABEL.match(line)
        if label:
            current = label.group(1)
            definitions.add(current)
            continue
        if not re.match(r"^\s*[0-9a-fA-F]+:\s", line):
            continue
        call = BRANCH.search(line)
        if not call:
            continue
        target = call.group(2) or call.group(1)
        if target in direct:
            direct[target] += 1
        if current in wrappers and target in SYSTEM_CALLS:
            wrappers[current][target] += 1
    return {"definitions": [name for name in ENTRY_POINTS if name in definitions],
            "direct_calls": direct,
            "wrapper_calls": wrappers,
            "analysis_limit": "Direct named ARM64 branches only; indirect calls, inlined paths and execution are not verified."}



# Count control-flow evidence locally, without exporting opcodes, addresses,
# registers, or the names of unrelated proprietary functions.
INSN = re.compile(r"^\s*[0-9a-fA-F]+:\s+(?:(?:[0-9a-fA-F]{2}|[0-9a-fA-F]{8})\s+)*([a-z][a-z0-9.]*)\b")
INDIRECT = {"br", "blr", "braa", "brab", "braaz", "brabz", "blraa", "blrab", "blraaz", "blrabz"}
RETURN = {"ret", "retaa", "retab"}

def control_flow_summary(disassembly):
    def empty():
        return {"instruction_records": 0, "indirect_transfers": 0,
                "returns": 0, "store_instructions": 0, "named_api_sequence": []}
    wrappers = {name: empty() for name in ENTRY_POINTS}
    callers = {}
    current = None
    for line in disassembly.splitlines():
        label = LABEL.match(line)
        if label:
            current = label.group(1)
            continue
        # Do not attribute instructions across Mach-O section boundaries.
        if line.strip().endswith("section"):
            current = None
            continue
        insn = INSN.match(line)
        if not insn:
            continue
        op = insn.group(1)
        if current in wrappers:
            w = wrappers[current]
            w["instruction_records"] += 1
            w["indirect_transfers"] += int(op in INDIRECT)
            w["returns"] += int(op in RETURN)
            w["store_instructions"] += int(op.startswith("st"))
        call = BRANCH.search(line)
        if call:
            target = call.group(2) or call.group(1)
            if current in wrappers and target in SYSTEM_CALLS:
                wrappers[current]["named_api_sequence"].append(target)
            if current and target in ENTRY_POINTS:
                callers.setdefault(current, set()).add(target)
    return {"wrappers": wrappers,
            "direct_caller_patterns": [
                {"entry_points": list(pattern), "function_count": count}
                for pattern, count in sorted(
                    Counter(tuple(sorted(v)) for v in callers.values()).items())],
            "limit": "Static instruction mnemonics and textual call order only. Not a control-flow graph, ABI signature, runtime ordering or proof of an interpreter integration boundary."}

# Scope to names and exact tokens; no inference that a found option works.
MODE_FLAGS = re.compile(rb"(?<![A-Za-z0-9_-])--(?:no-draw|no-ui|no-jit|disable-jit|no_jit|disable_jit|interpreter|interpret)(?![A-Za-z0-9_-])")
SYM_MODE = re.compile(r"(?:interpreter|interpretation|interpret_|no_?jit|disable_?jit|bytecode|vm_exec)", re.I)
SIM_JIT = re.compile(r"(?:_jit__modelZsimulationZ|_jit_function__modelZsimulationZ|_handle_request_compile_and_run__modelZsimulationZ)")
def mode_summary(raw, symbols):
    names = [line.split()[-1] for line in symbols.splitlines()
             if re.match(r"^\s*[0-9A-Fa-f]{8,16}\s", line) and line.split()]
    return {"known_flag_strings": sorted({m.group().decode("ascii") for m in MODE_FLAGS.finditer(raw)}),
            "possible_interpreter_symbol_count": sum(bool(SYM_MODE.search(n)) for n in names),
            "simulation_jit_symbol_count": sum(bool(SIM_JIT.search(n)) for n in names),
            "symbol_records_inspected": len(names),
            "limit": "Named symbol and exact flag-string evidence only. No proof an option is recognized, a backend exists, or JIT can be disabled."}

def audit(directory, tool):
    result = {}
    for name in BINARIES:
        path = directory / name
        raw = path.read_bytes()
        output = subprocess.check_output([tool, "--macho", "--arch=arm64", "--disassemble", "--symbolize-operands", str(path)], text=True, stderr=subprocess.PIPE)
        entry = summarize(output)
        entry["control_flow_evidence"] = control_flow_summary(output)
        symbols = subprocess.check_output([tool, "--macho", "--arch=arm64", "--syms", str(path)], text=True, stderr=subprocess.PIPE)
        entry["mode_evidence"] = mode_summary(raw, symbols)
        entry["sha256"] = hashlib.sha256(raw).hexdigest()
        entry["size"] = len(raw)
        if not entry["definitions"]:
            raise ValueError(f"{name}: no expected JIT labels; unsupported/stripped binary or disassembler output")
        result[name] = entry
    return {"binaries": result, "game_launch_authorized": False, "runtime_verified": False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("binary_directory", type=pathlib.Path)
    parser.add_argument("--objdump", default=None)
    parser.add_argument("--output", type=pathlib.Path)
    args = parser.parse_args()
    tool = args.objdump or shutil.which("llvm-objdump")
    if not tool and sys.platform == "darwin":
        tool = subprocess.check_output(["xcrun", "--find", "llvm-objdump"], text=True).strip()
    if not tool:
        parser.error("llvm-objdump required; use --objdump to specify its path")
    data = json.dumps(audit(args.binary_directory, tool), indent=2) + "\n"
    if args.output:
        with args.output.open("x", encoding="utf-8") as handle:
            handle.write(data)
    else:
        print(data, end="")


if __name__ == "__main__":
    main()
