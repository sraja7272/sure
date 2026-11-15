import { Controller } from "@hotwired/stimulus";

// Saves the Admin > Connectors switches shortly after they change. A burst of
// clicks becomes one save of the final state, and one "saved" notice is shown
// once the newest save has succeeded and the switches have been left alone for
// a moment. Each save carries this page's id and a counter so the server can
// ignore a save that reaches it after a newer one.
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
    this.sequence = 0;
    this.pending = false;
    this.clientIdTarget.value = `${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`;
    this.savedState = this.#currentState();
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
    this.pending = true;
    this.timeout = setTimeout(() => {
      this.pending = false;
      this.sequence += 1;
      this.sequenceTarget.value = this.sequence;
      this.element.requestSubmit();
    }, this.delayValue);
  }

  saved(event) {
    const { success, formSubmission } = event.detail;
    const submitted = Number(
      formSubmission?.formData?.get("sequence") ?? this.sequence,
    );

    // A newer change is waiting or was sent after this one: its own save will
    // report. A save Turbo aborted for a newer one has no success value.
    if (this.pending || submitted !== this.sequence || success === undefined)
      return;

    if (success) {
      this.savedState = this.#currentState();
      clearTimeout(this.noticeTimeout);
      this.noticeTimeout = setTimeout(
        () => this.#show(this.savedNoticeTarget),
        this.noticeDelayValue,
      );
    } else {
      this.#restoreSavedState();
      this.#show(this.failedAlertTarget);
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

  #restoreSavedState() {
    for (const input of this.#switches()) {
      if (input.name in this.savedState)
        input.checked = this.savedState[input.name];
    }
  }

  #show(template) {
    const tray = document.getElementById("notification-tray");
    if (tray) tray.append(template.content.cloneNode(true));
  }
}
