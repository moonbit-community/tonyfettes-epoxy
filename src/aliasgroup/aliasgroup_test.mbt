///|
/// inspect on a bare `Array[String]` trips a Show-vs-Debug deprecation; render
/// the list to a plain string first so the assertions stay warning-free.
fn show(names : Array[String]) -> String {
  "[" + names.join(", ") + "]"
}

///|
test "a name with no aliases yields nothing" {
  let g = @aliasgroup.Groups::from_edges([])
  inspect(show(g.aliases_of("glClear")), content="[]")
}

///|
test "a single edge links both directions" {
  let g = @aliasgroup.Groups::from_edges([
    { name: "glActiveTextureARB", target: "glActiveTexture" },
  ])
  inspect(show(g.aliases_of("glActiveTextureARB")), content="[glActiveTexture]")
  inspect(show(g.aliases_of("glActiveTexture")), content="[glActiveTextureARB]")
}

///|
test "edges sharing a target form one transitive group" {
  // both the OES and APPLE forms alias the core name
  let g = @aliasgroup.Groups::from_edges([
    { name: "glGenVertexArraysOES", target: "glGenVertexArrays" },
    { name: "glGenVertexArraysAPPLE", target: "glGenVertexArrays" },
  ])
  // each member sees the others, lexicographically, itself excluded
  inspect(
    show(g.aliases_of("glGenVertexArrays")),
    content="[glGenVertexArraysAPPLE, glGenVertexArraysOES]",
  )
  inspect(
    show(g.aliases_of("glGenVertexArraysOES")),
    content="[glGenVertexArrays, glGenVertexArraysAPPLE]",
  )
}

///|
test "a name absent from every edge yields nothing" {
  let g = @aliasgroup.Groups::from_edges([
    { name: "glActiveTextureARB", target: "glActiveTexture" },
  ])
  inspect(show(g.aliases_of("glClear")), content="[]")
}
