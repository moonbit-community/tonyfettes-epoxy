///|
/// The type vocabulary and mapping table that drive the binding generator.
///
/// Each GL typedef the generator can handle maps to a `TypeInfo`: the concrete
/// C type it resolves to (for the function-pointer cast) and the MoonBit type
/// it is exposed as. Both are enums — no stringly-typed spellings — so the
/// "GLenum is unsigned int / UInt" knowledge lives in exactly one place.

///|
/// A concrete C type. Leaves are real machine types (`c` gives the C
/// spelling); `Pointer` nests. Unlike a parsed declarator, every leaf is known,
/// so `c` is total.
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
  Pointer(CType, is_const~ : Bool)
}

///|
/// The C spelling, for the generated function-pointer cast.
pub fn CType::c(self : CType) -> String {
  match self {
    Void => "void"
    UInt => "unsigned int"
    Int => "int"
    Float => "float"
    Double => "double"
    Int64 => "int64_t"
    UInt64 => "uint64_t"
    Byte => "unsigned char"
    SByte => "signed char"
    Char => "char"
    Short => "short"
    UShort => "unsigned short"
    IntPtr => "intptr_t"
    SizePtr => "ssize_t"
    // A `const` qualifier reads differently depending on what it qualifies: when
    // the pointee is a scalar leaf, west-const (`const char *`) is idiomatic;
    // when the pointee is itself a pointer, the `const` must follow that
    // pointer's stars (`const char *const *`) rather than pile up in front.
    // Splitting on the pointee's shape keeps single-level casts byte-identical
    // and renders nested const pointers correctly.
    Pointer(inner, is_const~) =>
      match inner {
        Pointer(_, ..) => inner.c() + (if is_const { " const *" } else { " *" })
        _ => (if is_const { "const " } else { "" }) + inner.c() + " *"
      }
  }
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
    Array(e) => "FixedArray[\{e.moonbit()}]"
  }
}

///|
/// The C type a value arrives as on the shim side (the MoonBit ABI spelling).
pub fn MType::c_abi(self : MType) -> String {
  match self {
    UInt => "uint32_t"
    Int => "int32_t"
    Float => "float"
    Double => "double"
    Int64 => "int64_t"
    UInt64 => "uint64_t"
    Int16 => "int16_t"
    UInt16 => "uint16_t"
    Bool => "int32_t"
    Bytes => "moonbit_bytes_t"
    Array(e) => e.c_abi() + " *"
  }
}

///|
/// Pointer-like types must be `#borrow`'d into the extern.
pub fn MType::is_pointer(self : MType) -> Bool {
  match self {
    Bytes | Array(_) => true
    _ => false
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
}

///|
/// Look up a GL typedef, or None if the generator can't express it.
pub fn lookup(name : String) -> TypeInfo? {
  table.get(name)
}
