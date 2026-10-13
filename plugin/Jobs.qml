import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// Runs `paattu --json ...` commands one after another and reports progress.
// Each command prints JSON lines: progress events, then done or error.
Item {
  id: root

  property var queue: []
  property var current: null
  property string message: ""
  property int step: 0
  property int total: 0
  property string lastError: ""
  property string lastDone: ""
  readonly property bool busy: current !== null

  signal finished(var job, bool ok, var event)

  // args: CLI arguments after `paattu --json`; label: what the UI shows.
  function run(args, label, onDone) {
    var job = { args: args, label: label || "", onDone: onDone || null }
    queue = queue.concat([job])
    if (!current) startNext()
    return job
  }

  function startNext() {
    if (queue.length === 0) {
      current = null
      return
    }
    current = queue[0]
    queue = queue.slice(1)
    message = current.label
    step = 0
    total = 0
    lastEvent = null
    proc.command = ["paattu", "--json"].concat(current.args)
    proc.running = true
  }

  property var lastEvent: null

  function handle(line) {
    var e = Model.parseEvent(line)
    if (!e) return
    if (e.event === "progress") {
      message = e.message || message
      if (e.total) { step = e.step || 0; total = e.total }
    } else if (e.event === "done" || e.event === "error") {
      lastEvent = e
    }
  }

  Process {
    id: proc
    stdout: SplitParser { onRead: function(line) { root.handle(line) } }
    stderr: StdioCollector { id: stderrText }
    onExited: function(code) {
      var job = root.current
      var e = root.lastEvent || { event: code === 0 ? "done" : "error",
        message: code === 0 ? "" : (String(stderrText.text || "").trim().split("\n").pop() || "paattu failed") }
      var ok = e.event === "done"
      if (ok) {
        root.lastDone = e.message || ""
        root.lastError = ""
      } else {
        root.lastError = e.message || "Something went wrong"
      }
      root.message = ""
      if (job && job.onDone) job.onDone(ok, e)
      root.finished(job, ok, e)
      root.startNext()
    }
  }
}
