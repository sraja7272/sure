import { Controller } from "@hotwired/stimulus";

// Saves the Admin > Connectors switches shortly after they change. A burst of
// clicks becomes one save of the final state. Each save carries this page's
// id and a counter so the server can ignore a save that reaches it after a
// newer one.
export default class extends Controller {
  static targets = ["clientId", "sequence"];
  static values = { delay: { type: Number, default: 400 } };

  connect() {
    this.sequence = 0;
    this.clientIdTarget.value = `${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`;
  }

  disconnect() {
    clearTimeout(this.timeout);
  }

  save() {
    clearTimeout(this.timeout);
    this.timeout = setTimeout(() => {
      this.sequence += 1;
      this.sequenceTarget.value = this.sequence;
      this.element.requestSubmit();
    }, this.delayValue);
  }
}
