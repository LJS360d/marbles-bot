class GuildsService {
	public readonly spawnsMap = new Map<string, number>();

	public getLatestSpawn(guildId: string) {
		return this.spawnsMap.get(guildId) ?? 0;
	}

	public setLatestSpawn(guildId: string) {
		this.spawnsMap.set(guildId, new Date().getTime());
	}
}

export default GuildsService;
