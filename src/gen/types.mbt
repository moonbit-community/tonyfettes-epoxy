///|
/// The type mapping table that drives the binding generator.
///
/// Every `GLxxx` typedef found in the Khronos registry (`registry/gl.xml`)
/// collapses onto a small set of underlying C representations. The generator
/// reads each command's `<ptype>` from the XML and looks it up here to decide:
///   - the MoonBit-side type to expose,
///   - the C type to emit in the generated shim,
///   - how the argument/return value must be marshalled across the FFI boundary.
///
/// This is the single source of truth; extending GL coverage is mostly a matter
/// of keeping this table complete.

///|
/// How a value crosses the MoonBit <-> C FFI boundary.
pub enum FfiCategory {
  /// Plain by-value number. Direct 1:1 mapping, no marshalling.
  Scalar
  /// Pointer-width integer (offset/size). MoonBit `Int64` -> C `intptr_t`/
  /// `ssize_t`. MUST NOT be narrowed to 32-bit or it truncates on 64-bit.
  PtrSized
  /// Pointer to data: arrays, pixel buffers, in/out params, C strings.
  /// Marshalled as `Bytes` / `FixedArray[T]` (passed via `#borrow`) or an
  /// `#external` raw pointer.
  Pointer
  /// Opaque handle (`GLsync`, `GLhandleARB`, egl image, ...). `#external type`.
  Opaque
  /// Function-pointer callback (`GLDEBUGPROC` family). Needs a MoonBit->C
  /// trampoline; deferred in the MVP.
  Callback
} derive(Show, Eq)

///|
/// One row of the mapping table.
pub struct TypeMapping {
  /// The registry typedef name, e.g. "GLenum".
  gl_type : String
  /// The C type the generated shim should use, e.g. "unsigned int".
  c_type : String
  /// The MoonBit type exposed to callers, e.g. "UInt".
  moonbit_type : String
  /// How it is marshalled.
  category : FfiCategory
} derive(Show, Eq)

///|
/// The canonical table. Synonym typedefs (e.g. GLclampf ~ GLfloat) are listed
/// explicitly so a registry lookup never misses.
pub let table : Array[TypeMapping] = [
  // --- 1. Scalars: ~95% of all parameters -------------------------------
  TypeMapping::{
    gl_type: "GLenum",
    c_type: "unsigned int",
    moonbit_type: "UInt",
    category: Scalar,
  },
  TypeMapping::{
    gl_type: "GLbitfield",
    c_type: "unsigned int",
    moonbit_type: "UInt",
    category: Scalar,
  },
  TypeMapping::{
    gl_type: "GLuint",
    c_type: "unsigned int",
    moonbit_type: "UInt",
    category: Scalar,
  },
  TypeMapping::{
    gl_type: "GLint",
    c_type: "int",
    moonbit_type: "Int",
    category: Scalar,
  },
  TypeMapping::{
    gl_type: "GLsizei",
    c_type: "int",
    moonbit_type: "Int",
    category: Scalar,
  },
  TypeMapping::{
    gl_type: "GLfixed",
    c_type: "int",
    moonbit_type: "Int",
    category: Scalar,
  },
  TypeMapping::{
    gl_type: "GLclampx",
    c_type: "int",
    moonbit_type: "Int",
    category: Scalar,
  },
  TypeMapping::{
    gl_type: "GLfloat",
    c_type: "float",
    moonbit_type: "Float",
    category: Scalar,
  },
  TypeMapping::{
    gl_type: "GLclampf",
    c_type: "float",
    moonbit_type: "Float",
    category: Scalar,
  },
  TypeMapping::{
    gl_type: "GLdouble",
    c_type: "double",
    moonbit_type: "Double",
    category: Scalar,
  },
  TypeMapping::{
    gl_type: "GLclampd",
    c_type: "double",
    moonbit_type: "Double",
    category: Scalar,
  },
  TypeMapping::{
    gl_type: "GLint64",
    c_type: "int64_t",
    moonbit_type: "Int64",
    category: Scalar,
  },
  TypeMapping::{
    gl_type: "GLint64EXT",
    c_type: "int64_t",
    moonbit_type: "Int64",
    category: Scalar,
  },
  TypeMapping::{
    gl_type: "GLuint64",
    c_type: "uint64_t",
    moonbit_type: "UInt64",
    category: Scalar,
  },
  TypeMapping::{
    gl_type: "GLuint64EXT",
    c_type: "uint64_t",
    moonbit_type: "UInt64",
    category: Scalar,
  },
  TypeMapping::{
    gl_type: "GLbyte",
    c_type: "signed char",
    moonbit_type: "Int",
    category: Scalar,
  },
  TypeMapping::{
    gl_type: "GLchar",
    c_type: "char",
    moonbit_type: "Int",
    category: Scalar,
  },
  TypeMapping::{
    gl_type: "GLcharARB",
    c_type: "char",
    moonbit_type: "Int",
    category: Scalar,
  },
  TypeMapping::{
    gl_type: "GLboolean",
    c_type: "unsigned char",
    moonbit_type: "Bool",
    category: Scalar,
  },
  TypeMapping::{
    gl_type: "GLubyte",
    c_type: "unsigned char",
    moonbit_type: "Int",
    category: Scalar,
  },
  TypeMapping::{
    gl_type: "GLshort",
    c_type: "short",
    moonbit_type: "Int",
    category: Scalar,
  },
  TypeMapping::{
    gl_type: "GLushort",
    c_type: "unsigned short",
    moonbit_type: "Int",
    category: Scalar,
  },
  TypeMapping::{
    gl_type: "GLhalf",
    c_type: "unsigned short",
    moonbit_type: "Int",
    category: Scalar,
  },
  TypeMapping::{
    gl_type: "GLhalfARB",
    c_type: "unsigned short",
    moonbit_type: "Int",
    category: Scalar,
  },
  TypeMapping::{
    gl_type: "GLhalfNV",
    c_type: "unsigned short",
    moonbit_type: "Int",
    category: Scalar,
  },

  // --- 2. Pointer-width integers (offsets / sizes) ----------------------
  TypeMapping::{
    gl_type: "GLintptr",
    c_type: "intptr_t",
    moonbit_type: "Int64",
    category: PtrSized,
  },
  TypeMapping::{
    gl_type: "GLintptrARB",
    c_type: "intptr_t",
    moonbit_type: "Int64",
    category: PtrSized,
  },
  TypeMapping::{
    gl_type: "GLsizeiptr",
    c_type: "ssize_t",
    moonbit_type: "Int64",
    category: PtrSized,
  },
  TypeMapping::{
    gl_type: "GLsizeiptrARB",
    c_type: "ssize_t",
    moonbit_type: "Int64",
    category: PtrSized,
  },
  TypeMapping::{
    gl_type: "GLvdpauSurfaceNV",
    c_type: "intptr_t",
    moonbit_type: "Int64",
    category: PtrSized,
  },

  // --- 3. Pointers: data / arrays / strings / in-out params -------------
  // The generator emits `Bytes` (via #borrow) for these; `void` here is the
  // pointee fallback, the actual pointee type comes from the command sig.
  TypeMapping::{
    gl_type: "GLvoid",
    c_type: "void",
    moonbit_type: "Bytes",
    category: Pointer,
  },

  // --- 4. Opaque handles ------------------------------------------------
  TypeMapping::{
    gl_type: "GLsync",
    c_type: "GLsync",
    moonbit_type: "GLsync",
    category: Opaque,
  },
  TypeMapping::{
    gl_type: "GLhandleARB",
    c_type: "GLhandleARB",
    moonbit_type: "GLhandleARB",
    category: Opaque,
  },
  TypeMapping::{
    gl_type: "GLeglImageOES",
    c_type: "void*",
    moonbit_type: "GLeglImageOES",
    category: Opaque,
  },
  TypeMapping::{
    gl_type: "GLeglClientBufferEXT",
    c_type: "void*",
    moonbit_type: "GLeglClientBufferEXT",
    category: Opaque,
  },

  // --- 5. Callbacks (deferred in MVP) -----------------------------------
  TypeMapping::{
    gl_type: "GLDEBUGPROC",
    c_type: "GLDEBUGPROC",
    moonbit_type: "GLDEBUGPROC",
    category: Callback,
  },
  TypeMapping::{
    gl_type: "GLDEBUGPROCARB",
    c_type: "GLDEBUGPROCARB",
    moonbit_type: "GLDEBUGPROC",
    category: Callback,
  },
  TypeMapping::{
    gl_type: "GLDEBUGPROCKHR",
    c_type: "GLDEBUGPROCKHR",
    moonbit_type: "GLDEBUGPROC",
    category: Callback,
  },
  TypeMapping::{
    gl_type: "GLDEBUGPROCAMD",
    c_type: "GLDEBUGPROCAMD",
    moonbit_type: "GLDEBUGPROC",
    category: Callback,
  },
  TypeMapping::{
    gl_type: "GLVULKANPROCNV",
    c_type: "GLVULKANPROCNV",
    moonbit_type: "GLVULKANPROCNV",
    category: Callback,
  },
]

///|
/// Look up a registry typedef. Returns None for unknown types so the generator
/// can report (and the user can extend the table) instead of emitting wrong code.
pub fn lookup(gl_type : String) -> TypeMapping? {
  for m in table {
    if m.gl_type == gl_type {
      return Some(m)
    }
  }
  None
}
