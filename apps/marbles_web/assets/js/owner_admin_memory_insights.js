const STORAGE_KEY = "owner_admin_memory_insights"

const OwnerAdminMemoryInsights = {
  mounted() {
    const raw = localStorage.getItem(STORAGE_KEY)
    const enabled = raw !== "false"
    this.pushEvent("memory_insights_init", { enabled })
    this.handleEvent("persist_memory_insights", ({ enabled }) => {
      localStorage.setItem(STORAGE_KEY, String(enabled))
    })
  }
}

export default OwnerAdminMemoryInsights
