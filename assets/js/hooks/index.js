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
  }
};

export default Hooks;
