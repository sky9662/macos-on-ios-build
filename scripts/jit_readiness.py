"""Fail-closed launch readiness model; no debugger or entitlement manipulation."""
from dataclasses import dataclass

@dataclass(frozen=True)
class Readiness:
    debug_authorized: bool = False
    pairing_readable: bool = False
    tunnel_ready: bool = False
    debugger_attached: bool = False
    allocator_compatible: bool = False
    execution_verified: bool = False
    imports_resolved: bool = False

    def blocker(self):
        for field, reason in (
            ("debug_authorized", "debug authorization missing"),
            ("pairing_readable", "pairing file unavailable"),
            ("tunnel_ready", "tunnel unavailable"),
            ("debugger_attached", "debugger not attached"),
            ("allocator_compatible", "allocator compatibility unverified"),
            ("execution_verified", "execution unverified"),
            ("imports_resolved", "game imports unresolved"),
        ):
            if not getattr(self, field):
                return reason
        return None
