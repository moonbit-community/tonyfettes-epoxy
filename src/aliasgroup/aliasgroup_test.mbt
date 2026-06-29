///|
test "a name with no aliases yields nothing" {
  let g = @aliasgroup.Groups::from_edges([])
  debug_inspect(g.aliases_of("glClear"), content="[]")
}

///|
test "a single edge links both directions" {
  let g = @aliasgroup.Groups::from_edges([
    { name: "glActiveTextureARB", target: "glActiveTexture" },
  ])
  debug_inspect(g.aliases_of("glActiveTextureARB"), content=(
    #|["glActiveTexture"]
  ))
  debug_inspect(g.aliases_of("glActiveTexture"), content=(
    #|["glActiveTextureARB"]
  ))
}

///|
test "edges sharing a target form one transitive group" {
  // both the OES and APPLE forms alias the core name
  let g = @aliasgroup.Groups::from_edges([
    { name: "glGenVertexArraysOES", target: "glGenVertexArrays" },
    { name: "glGenVertexArraysAPPLE", target: "glGenVertexArrays" },
  ])
  // each member sees the others, lexicographically, itself excluded
  debug_inspect(g.aliases_of("glGenVertexArrays"), content=(
    #|["glGenVertexArraysAPPLE", "glGenVertexArraysOES"]
  ))
  debug_inspect(g.aliases_of("glGenVertexArraysOES"), content=(
    #|["glGenVertexArrays", "glGenVertexArraysAPPLE"]
  ))
}

///|
test "a name absent from every edge yields nothing" {
  let g = @aliasgroup.Groups::from_edges([
    { name: "glActiveTextureARB", target: "glActiveTexture" },
  ])
  debug_inspect(g.aliases_of("glClear"), content="[]")
}
