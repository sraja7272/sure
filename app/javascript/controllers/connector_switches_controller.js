import { Controller } from "@hotwired/stimulus";

// Saves the Admin > Connectors switches shortly after they change. A burst of
// clicks becomes one save of the final state, and one "saved" notice is shown
// once the switches have been left alone for a moment. Each save carries this
// page's id and a counter so the server can ignore a save that reaches it
// after a newer one.
export default class extends Controller {
  static targets = ["clientId", "sequence", "notice"];
  static values = {
    delay: { type: Number, default: 400 },
    noticeDelay: { type: Number, default: 1500 },
  };

  connect() {
    this.sequence = 0;
    this.clientIdTarget.value = `${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`;
  }

  disconnect() {
    clearTimeout(this.timeout);
    clearTimeout(this.noticeTimeout);
  }

  save() {
    clearTimeout(this.timeout);
    clearTimeout(this.noticeTimeout);
    this.timeout = setTimeout(() => {
      this.sequence += 1;
      this.sequenceTarget.value = this.sequence;
      this.element.requestSubmit();
    }, this.delayValue);
  }

  saved(event) {
    if (!event.detail.success) return;

    clearTimeout(this.noticeTimeout);
    this.noticeTimeout = setTimeout(
      () => this.#showNotice(),
      this.noticeDelayValue,
    );
  }

  #showNotice() {
    const tray = document.getElementById("notification-tray");
    if (tray) tray.append(this.noticeTarget.content.cloneNode(true));
  }
}
