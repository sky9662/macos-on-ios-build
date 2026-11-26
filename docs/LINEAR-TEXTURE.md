# GLES3 linear texture storage — public build round 43

The Khronos EXT/OES_texture_buffer specifications require GLES 3.1; Apple documents iOS OpenGLES through 3.0. Do not assume native buffer-texture support. The shim exposes glTexBuffer only as native extension dispatch with an explicit error when unavailable.

A separate source-level API, TCUploadLinearTexture2D, uses the actual GLES3 pixel unpack buffer path to upload linear RGBA8 or RGBA32F texels into a bounded 2D texture. It supports partial final rows, restores the prior texture binding, pixel unpack buffer and unpack parameters, and rejects a mapped or undersized source. The caller must own the texture, request an appropriate width limit, explicitly upload again after source mutation, and adapt shader indexing to sampler2D with integer coordinates (index % width, index / width). The padded tail is not a valid texel. This does not emulate desktop buffer texture aliasing, all formats, or arbitrary shaders.

The independent integrated probe tests three RGBA8 texels across two rows, source update, a float texel, state restoration and actual GPU readback. CI checks 12 portable layout cases and exported symbols; physical-device execution remains unverified. No game binaries or private device records. No JIT allocator change.

References: https://registry.khronos.org/OpenGL/extensions/EXT/EXT_texture_buffer.txt ; https://registry.khronos.org/OpenGL/extensions/OES/OES_texture_buffer.txt ; https://developer.apple.com/documentation/opengles .
