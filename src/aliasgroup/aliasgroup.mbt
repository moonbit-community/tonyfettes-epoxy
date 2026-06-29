///|
/// Grouping of mutually-aliased GL entrypoints, the data libepoxy needs to be
/// faithful: a single GL function often has several names — it appears first as
/// an extension (`glGenVertexArraysOES`, `...APPLE`) and later in core
/// (`glGenVertexArrays`) — and a given driver may export only some of them. The
/// registry records each relation as `<alias name="target"/>` inside a command.
///
/// libepoxy resolves an entrypoint by trying every name in its alias group in
/// turn, so a core call still resolves on a driver that only exports the
/// extension form. This package computes those groups (a disjoint-set / union
/// over the alias relation) so the generator can hand each binding its fallback
/// names. Pure and dependency-free, so it can be unit-tested in isolation.

///|
/// One `<alias>` relation from the registry: command `name` is declared to be
/// an alias of `target`.
pub(all) struct Edge {
  name : String
  target : String
}

///|
/// A disjoint-set forest over entrypoint names; two names share a root iff the
/// registry links them (transitively) by `<alias>`.
pub struct Groups {
  parent : Map[String, String]
}

///|
/// The representative of `x`'s set (walks parent pointers to the root). A name
/// never seen as an edge endpoint is its own root.
fn Groups::find(self : Groups, x : String) -> String {
  let mut root = x
  while self.parent.get(root) is Some(p) && p != root {
    root = p
  }
  root
}

///|
/// Build groups from the registry's alias edges, unioning each `name` with its
/// `target`. The result holds every name that appears in any edge.
pub fn Groups::from_edges(edges : Array[Edge]) -> Groups {
  let parent : Map[String, String] = {}
  let groups = Groups::{ parent, }
  fn ensure(x : String) -> Unit {
    if parent.get(x) is None {
      parent[x] = x
    }
  }

  for e in edges {
    ensure(e.name)
    ensure(e.target)
    let ra = groups.find(e.name)
    let rb = groups.find(e.target)
    if ra != rb {
      parent[ra] = rb
    }
  }
  groups
}

///|
/// Lexicographic (dictionary) order over code units. MoonBit's default
/// `String::compare` orders by length first, which would read as unsorted
/// (`...OES` before `...APPLE`); this gives the intuitive A-before-O order.
fn lex_compare(a : String, b : String) -> Int {
  let limit = if a.length() <= b.length() { a.length() } else { b.length() }
  for i in 0..<limit {
    let order = a[i].to_int().compare(b[i].to_int())
    if order != 0 {
      return order
    }
  }
  a.length().compare(b.length())
}

///|
/// The other entrypoints equivalent to `name` — its fallback resolution names,
/// in lexicographic order for determinism. Excludes `name` itself (the call
/// site's own spelling is tried first elsewhere). A name with no aliases yields
/// `[]`.
pub fn Groups::aliases_of(self : Groups, name : String) -> Array[String] {
  guard self.parent.get(name) is Some(_) else { return [] }
  let root = self.find(name)
  let others = []
  for entry, _ in self.parent {
    if entry != name && self.find(entry) == root {
      others.push(entry)
    }
  }
  others.sort_by(lex_compare)
  others
}
