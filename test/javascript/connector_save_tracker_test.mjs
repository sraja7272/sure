import { describe, it } from "node:test"
import assert from "node:assert/strict"

// The tracker has no imports, so the shipped module is imported as written.
const { ConnectorSaveTracker } = await import(
  new URL("../../app/javascript/utils/connector_save_tracker.js", import.meta.url)
)

const A = { "connectors[plaid]": true, "connectors[simplefin]": true }
const B = { "connectors[plaid]": true, "connectors[simplefin]": false }
const C = { "connectors[plaid]": false, "connectors[simplefin]": true }

describe("ConnectorSaveTracker", () => {
  it("reports a lone successful save", () => {
    const tracker = new ConnectorSaveTracker(A)
    tracker.changed()
    const sequence = tracker.submit(B)

    assert.equal(tracker.finished(sequence, true), "saved")
    assert.deepEqual(tracker.confirmedState, B)
  })

  it("stays quiet about a save while a newer change is pending, but records it", () => {
    const tracker = new ConnectorSaveTracker(A)
    const first = tracker.submit(B)
    tracker.changed()

    assert.equal(tracker.finished(first, true), "ignore")
    assert.deepEqual(tracker.confirmedState, B)
  })

  it("restores the newest confirmed state when a later save fails", () => {
    const tracker = new ConnectorSaveTracker(A)
    const first = tracker.submit(B)
    tracker.changed()
    tracker.finished(first, true)
    const second = tracker.submit(C)

    assert.equal(tracker.finished(second, false), "failed")
    assert.deepEqual(tracker.confirmedState, B)
  })

  it("ignores a save the browser aborted for a newer one", () => {
    const tracker = new ConnectorSaveTracker(A)
    const first = tracker.submit(B)
    const second = tracker.submit(C)

    assert.equal(tracker.finished(first, undefined), "ignore")
    assert.equal(tracker.finished(second, true), "saved")
    assert.deepEqual(tracker.confirmedState, C)
  })

  it("never lets an older success replace a newer confirmed state", () => {
    const tracker = new ConnectorSaveTracker(A)
    const first = tracker.submit(B)
    const second = tracker.submit(C)
    tracker.finished(second, true)

    assert.equal(tracker.finished(first, true), "ignore")
    assert.deepEqual(tracker.confirmedState, C)
  })

  it("keeps the starting state when the only save fails", () => {
    const tracker = new ConnectorSaveTracker(A)
    const sequence = tracker.submit(B)

    assert.equal(tracker.finished(sequence, false), "failed")
    assert.deepEqual(tracker.confirmedState, A)
  })
})
