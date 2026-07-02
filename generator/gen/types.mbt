///|
/// The type vocabulary and mapping table that drive the binding generator.
///
/// Each GL typedef the generator can handle maps to a `TypeInfo`: the concrete
/// C type it resolves to (for the function-pointer cast) and the MoonBit type
/// it is exposed as. Both are enums — no stringly-typed spellings — so the
/// "GLenum is unsigned int / UInt" knowledge lives in exactly one place.

///|
/// A concrete C type — the resolved ABI of a GL typedef. It tags how a value is
/// narrowed on return (`narrow_of`) and how a pointee classifies into a MoonBit
/// array/bytes type (`pointer_mtype`); unlike a parsed declarator, every leaf is
/// known.
pub(all) enum CType {
  Void
  UInt // unsigned int
  Int // int
  Float
  Double
  Int64 // int64_t
  UInt64 // uint64_t
  Byte // unsigned char
  SByte // signed char
  Char // char
  Short // short
  UShort // unsigned short
  IntPtr // intptr_t
  SizePtr // ssize_t
  // An opaque object handle (`GLsync`, `GLeglImageOES`, …). Every GL object
  // pointer shares the `void *` ABI, so the cast needs no GL headers and no
  // per-handle spelling — the distinction lives on the MoonBit side instead.
  OpaquePtr
  Pointer(CType, is_const~ : Bool)
}

///|
/// A MoonBit type appearing in a generated binding. It knows how to print
/// itself and how it crosses the C FFI boundary.
pub(all) enum MType {
  UInt
  Int
  Float
  Double
  Int64
  UInt64
  Int16 // only as an array element; 16-bit scalars pass by value as Int
  UInt16 // ditto — also carries GLhalf, whose bits we hand through verbatim
  Bool
  Bytes
  // An opaque GL object handle, named by the MoonBit external type it is
  // exposed as (`GLsync`, `GLeglImageOES`, …). Crosses the FFI as a bare
  // pointer; distinct names keep the handles from being interchangeable.
  Handle(String)
  Array(MType) // FixedArray[elem]
}

///|
/// The MoonBit-source spelling, e.g. `UInt`, `FixedArray[Float]`.
pub fn MType::moonbit(self : MType) -> String {
  match self {
    UInt => "UInt"
    Int => "Int"
    Float => "Float"
    Double => "Double"
    Int64 => "Int64"
    UInt64 => "UInt64"
    Int16 => "Int16"
    UInt16 => "UInt16"
    Bool => "Bool"
    Bytes => "Bytes"
    Handle(name) => name
    Array(e) => "FixedArray[\{e.moonbit()}]"
  }
}

///|
/// Pointer-like types must be borrowed into a raw pointer before the FuncRef
/// call (a `FixedArray`/`Bytes` is a MoonBit object, not a bare `T *`).
pub fn MType::is_pointer(self : MType) -> Bool {
  match self {
    Bytes | Array(_) => true
    _ => false
  }
}

///|
/// The type this value takes in a `FuncRef` signature — the spelling that lowers
/// to the exact C ABI of the resolved GL function pointer. Scalars and opaque
/// handles keep their MoonBit type (it already lowers 1:1); array/bytes params
/// instead cross as a raw `@c.Pointer[elem]`, the borrowed data pointer that
/// matches `T *`.
pub fn MType::funcref_type(self : MType) -> String {
  match self {
    Bytes => "@c.Pointer[Byte]"
    Array(e) => "@c.Pointer[\{e.moonbit()}]"
    _ => self.moonbit()
  }
}

///|
/// How a scalar return is recovered from the `int32_t`-wide value MoonBit reads
/// out of a `FuncRef` call. MoonBit lowers every sub-word return (`Byte`,
/// `Int16`, `Bool`, …) to `int32_t` and reads the whole return register with no
/// narrowing, so a GL function that returns `unsigned char`/`short` leaves the
/// high bits unspecified (the psABI only fixes the low N). We always mask/sign-
/// extend back to the real width — equivalent to the `(T)` cast the old C shim
/// performed, but done MoonBit-side.
pub enum Narrow {
  None // already full-width (Int/UInt/Float/.../handle): pass through
  MaskU8 // unsigned char  -> & 0xFF
  SignU8 // signed char    -> (x << 24) >> 24
  MaskU16 // unsigned short -> & 0xFFFF
  SignU16 // short          -> (x << 16) >> 16
  BoolU8 // GLboolean      -> (x & 0xFF) != 0
}

///|
/// The narrowing a scalar return needs, from its real C type (`cast`) and the
/// MoonBit type it is exposed as (`mty` distinguishes `GLboolean` from `GLubyte`,
/// which share `unsigned char`).
pub fn narrow_of(cast : CType, mty : MType) -> Narrow {
  match (cast, mty) {
    (Byte, Bool) => BoolU8
    (Byte, _) => MaskU8
    (SByte, _) | (Char, _) => SignU8
    (UShort, _) => MaskU16
    (Short, _) => SignU16
    _ => None
  }
}

///|
/// The FuncRef return type for a scalar return: sub-word returns come back as
/// `Int` (MoonBit cannot express a narrower return) and are narrowed afterwards;
/// everything else returns its natural MoonBit type.
pub fn funcref_ret_type(cast : CType, mty : MType) -> String {
  match narrow_of(cast, mty) {
    None => mty.moonbit()
    _ => "Int"
  }
}

///|
/// How a GL typedef maps: its concrete C type and its MoonBit type. Both are
/// needed because neither determines the other — e.g. `GLboolean` and `GLubyte`
/// share the C type `unsigned char` but differ in MoonBit (`Bool` vs `Int`).
pub struct TypeInfo {
  c_type : CType
  m_type : MType
}

///|
/// The mapping table: every GL typedef the generator can express, keyed by its
/// registry name. Typedefs absent here (opaque handles like `GLsync`, callback
/// types like `GLDEBUGPROC`) are simply unsupported — the command is skipped.
pub let table : Map[String, TypeInfo] = {
  // unsigned 32-bit
  "GLenum": { c_type: UInt, m_type: UInt },
  "GLbitfield": { c_type: UInt, m_type: UInt },
  "GLuint": { c_type: UInt, m_type: UInt },
  // signed 32-bit
  "GLint": { c_type: Int, m_type: Int },
  "GLsizei": { c_type: Int, m_type: Int },
  "GLfixed": { c_type: Int, m_type: Int },
  "GLclampx": { c_type: Int, m_type: Int },
  // floating point
  "GLfloat": { c_type: Float, m_type: Float },
  "GLclampf": { c_type: Float, m_type: Float },
  "GLdouble": { c_type: Double, m_type: Double },
  "GLclampd": { c_type: Double, m_type: Double },
  // 64-bit
  "GLint64": { c_type: Int64, m_type: Int64 },
  "GLint64EXT": { c_type: Int64, m_type: Int64 },
  "GLuint64": { c_type: UInt64, m_type: UInt64 },
  "GLuint64EXT": { c_type: UInt64, m_type: UInt64 },
  // byte-sized (GLboolean vs GLubyte differ in MoonBit)
  "GLbyte": { c_type: SByte, m_type: Int },
  "GLchar": { c_type: Char, m_type: Int },
  "GLcharARB": { c_type: Char, m_type: Int },
  "GLboolean": { c_type: Byte, m_type: Bool },
  "GLubyte": { c_type: Byte, m_type: Int },
  // 16-bit (by value only; no native fixed-width array)
  "GLshort": { c_type: Short, m_type: Int },
  "GLushort": { c_type: UShort, m_type: Int },
  "GLhalf": { c_type: UShort, m_type: Int },
  "GLhalfARB": { c_type: UShort, m_type: Int },
  "GLhalfNV": { c_type: UShort, m_type: Int },
  // pointer-width integers (offsets / sizes)
  "GLintptr": { c_type: IntPtr, m_type: Int64 },
  "GLintptrARB": { c_type: IntPtr, m_type: Int64 },
  "GLsizeiptr": { c_type: SizePtr, m_type: Int64 },
  "GLsizeiptrARB": { c_type: SizePtr, m_type: Int64 },
  "GLvdpauSurfaceNV": { c_type: IntPtr, m_type: Int64 },
  // opaque object handles: pointer-valued tokens received from GL and handed
  // back unchanged. `GLhandleARB` is deliberately absent — it is `unsigned int`
  // on most platforms but `void *` on Apple, a platform-variant ABI this
  // single-ABI, header-free generator cannot express without miscompiling one
  // of them (its modern `GLuint` replacement, glCreateProgram &c., is bound).
  "GLsync": { c_type: OpaquePtr, m_type: Handle("GLsync") },
  "GLeglImageOES": { c_type: OpaquePtr, m_type: Handle("GLeglImageOES") },
  "GLeglClientBufferEXT": {
    c_type: OpaquePtr,
    m_type: Handle("GLeglClientBufferEXT"),
  },
  "GLVULKANPROCNV": { c_type: OpaquePtr, m_type: Handle("GLVULKANPROCNV") },
}

///|
/// Look up a GL typedef, or None if the generator can't express it.
pub fn lookup(name : String) -> TypeInfo? {
  table.get(name)
}
