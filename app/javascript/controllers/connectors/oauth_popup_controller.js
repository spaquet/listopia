import { Controller } from "@hotwired/stimulus";

// Controller for handling OAuth popup flows
export default class extends Controller {
  static targets = ["connectButton"];
  static values = { provider: String, authUrl: String };

  connect() {
    this.connectButtonTargets.forEach((button) => {
      button.addEventListener("click", (e) => this.authorize(e));
    });
  }

  authorize(event) {
    event.preventDefault();

    const provider = event.target.dataset.provider;
    const width = 500;
    const height = 600;
    const left = window.screenX + (window.outerWidth - width) / 2;
    const top = window.screenY + (window.outerHeight - height) / 2;

    const popup = window.open(
      this.authUrlValue,
      "ConnectorAuth",
      `width=${width},height=${height},left=${left},top=${top}`
    );

    // Poll the popup to see when it closes, then refresh the page
    const interval = setInterval(() => {
      if (popup.closed) {
        clearInterval(interval);
        // Refresh the page to show the newly connected account
        window.location.reload();
      }
    }, 1000);
  }
}
