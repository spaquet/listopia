import { Application } from "@hotwired/stimulus"
import TextareaAutogrow from "stimulus-textarea-autogrow"
import CharacterCounter from "@stimulus-components/character-counter"
import ScrollTo from "@stimulus-components/scroll-to"
import RevealController from "@stimulus-components/reveal"
import Notification from "@stimulus-components/notification"

import "highlight.js/styles/github.css" // Moved from application.tailwind.css to ensure styles are applied

const application = Application.start()

// Register the stimulus components
application.register("textarea-autogrow", TextareaAutogrow)
application.register("character-counter", CharacterCounter)
application.register("scroll-to", ScrollTo)
application.register("reveal", RevealController)
application.register("notification", Notification)

// Configure Stimulus development experience
application.debug = false
window.Stimulus   = application

export { application }