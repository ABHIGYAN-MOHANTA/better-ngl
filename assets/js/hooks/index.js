let Hooks = {
  UserPersistence: {
    mounted() {
      // Get the stored user ID
      const storedUserId = localStorage.getItem("userId");
      const currentId = this.el.dataset.anonymousId;

      if (storedUserId) {
        // If we have a stored ID and it's different from the current one,
        // restore it and clean up the old one
        if (storedUserId !== currentId) {
          this.pushEvent("restore_user_id", {
            userId: storedUserId,
            previousId: currentId
          });
        }
      } else {
        // If no stored ID, store the current one
        localStorage.setItem("userId", currentId);
      }

      // Update stored ID when it changes
      this.handleEvent("user_id_updated", ({ userId }) => {
        localStorage.setItem("userId", userId);
      });
    }
  },
  ChatScroll: {
    mounted() {
      // Wait briefly for the DOM to be ready
      setTimeout(() => {
        this.scrollToBottom();
      }, 0);

      // Create observer for new messages
      const messagesContainer = this.el;
      if (messagesContainer) {
        this.observer = new MutationObserver(() => {
          this.scrollToBottom();
        });

        // Configure the observer to watch for child additions
        this.observer.observe(messagesContainer, {
          childList: true
        });
      }
    },

    destroyed() {
      if (this.observer) {
        this.observer.disconnect();
      }
    },

    scrollToBottom() {
      // this.el refers to the element with the phx-hook attribute
      const messagesContainer = this.el;
      if (messagesContainer) {
        // Only scroll if we're already near the bottom
        const isNearBottom =
          messagesContainer.scrollHeight - messagesContainer.scrollTop - messagesContainer.clientHeight < 100;

        if (isNearBottom) {
          messagesContainer.scrollTop = messagesContainer.scrollHeight;
        }
      }
    }
  }
};

export default Hooks;
