// Bookkeeping for the Admin > Connectors autosave: which save is the newest,
// what the server last confirmed, and what a failed save should restore.
// Kept free of the DOM so the ordering rules can be tested on their own.
export class ConnectorSaveTracker {
  constructor(initialState) {
    this.sequence = 0;
    this.confirmedSequence = 0;
    this.confirmedState = initialState;
    this.snapshots = new Map();
    this.pending = false;
  }

  // A switch changed and a save is scheduled but not yet sent.
  changed() {
    this.pending = true;
  }

  // A save is being sent with this state. Returns its sequence number.
  submit(state) {
    this.pending = false;
    this.sequence += 1;
    this.snapshots.set(this.sequence, state);
    return this.sequence;
  }

  // A save finished. `success` is true, false, or undefined for a request the
  // browser aborted. Returns what the page should do: "saved", "failed" or
  // "ignore" (a newer change will report for itself).
  finished(sequence, success) {
    // Remember what the server confirmed, even for a save a newer change has
    // overtaken, so a later failure restores the newest confirmed state.
    if (success === true && sequence > this.confirmedSequence) {
      this.confirmedSequence = sequence;
      this.confirmedState = this.snapshots.get(sequence) ?? this.confirmedState;
      for (const key of [...this.snapshots.keys()]) {
        if (key <= sequence) this.snapshots.delete(key);
      }
    }

    if (this.pending || sequence !== this.sequence || success === undefined)
      return "ignore";
    return success ? "saved" : "failed";
  }
}
