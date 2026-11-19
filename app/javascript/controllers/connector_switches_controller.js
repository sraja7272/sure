import { Controller } from "@hotwired/stimulus";
import { ConnectorSaveTracker } from "utils/connector_save_tracker";

// Saves the Admin > Connectors switches shortly after they change. A burst of
// clicks becomes one save of the final state, and one "saved" notice is shown
// once the newest save has succeeded and the switches have been left alone for
// a moment. Each save carries this page's id and a counter so the server can
// ignore a save that reaches it after a newer one; ConnectorSaveTracker keeps
// the client-side ordering.
export default class extends Controller {
  static targets = [
    "clientId",
    "sequence",
    "savedNotice",
    "noneEnabledAlert",
    "failedAlert",
  ];
  static values = {
    delay: { type: Number, default: 400 },
    noticeDelay: { type: Number, default: 1500 },
  };

  connect() {
    this.clientIdTarget.value = `${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`;
    this.tracker = new ConnectorSaveTracker(this.#currentState());
  }

  disconnect() {
    clearTimeout(this.timeout);
    clearTimeout(this.noticeTimeout);
  }

  save(event) {
    // At least one connector must stay on. Refuse here rather than sending a
    // save the server would reject, so it can't race with newer clicks.
    if (!this.#switches().some((input) => input.checked)) {
      event.target.checked = true;
      this.#show(this.noneEnabledAlertTarget);
      return;
    }

    clearTimeout(this.timeout);
    clearTimeout(this.noticeTimeout);
    this.tracker.changed();
    this.timeout = setTimeout(() => {
      this.sequenceTarget.value = this.tracker.submit(this.#currentState());
      this.element.requestSubmit();
    }, this.delayValue);
  }

  saved(event) {
    const { success, formSubmission } = event.detail;
    const sequence = Number(
      formSubmission?.formData?.get("sequence") ?? this.tracker.sequence,
    );

    switch (this.tracker.finished(sequence, success)) {
      case "saved":
        clearTimeout(this.noticeTimeout);
        this.noticeTimeout = setTimeout(
          () => this.#show(this.savedNoticeTarget),
          this.noticeDelayValue,
        );
        break;
      case "failed":
        this.#restore(this.tracker.confirmedState);
        this.#show(this.failedAlertTarget);
        break;
    }
  }

  #switches() {
    return Array.from(
      this.element.querySelectorAll(
        'input[type="checkbox"][name^="connectors["]',
      ),
    );
  }

  #currentState() {
    return Object.fromEntries(
      this.#switches().map((input) => [input.name, input.checked]),
    );
  }

  #restore(state) {
    for (const input of this.#switches()) {
      if (input.name in state) input.checked = state[input.name];
    }
  }

  #show(template) {
    const tray = document.getElementById("notification-tray");
    if (tray) tray.append(template.content.cloneNode(true));
  }
}
