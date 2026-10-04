import QtQuick
import "Model.js" as Model

// A row's apps as a model whose entries are kept while the row changes
// (Model.listOps): an app that goes takes its tile with it and the others
// keep theirs, so they glide to their new places instead of being drawn
// again in them. Each entry: `key` (the package) and `json` (the app).
ListModel {
  id: list
  property var apps: []
  onAppsChanged: {
    var keys = (apps || []).map(function(a) { return a.package }), old = []
    for (var i = 0; i < list.count; i++) old.push(list.get(i).key)
    Model.listOps(old, keys).forEach(function(o) {
      if (o.op === "remove") list.remove(o.at, 1)
      else if (o.op === "move") list.move(o.from, o.to, 1)
      else list.insert(o.at, { key: o.key, json: JSON.stringify(apps[o.at]) })
    })
    for (var j = 0; j < apps.length; j++) {
      var json = JSON.stringify(apps[j])
      if (list.get(j).json !== json) list.setProperty(j, "json", json)
    }
  }
}
