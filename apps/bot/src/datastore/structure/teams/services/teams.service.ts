import type { MarbleDocumentFields } from '../../marbles/models/marble.model';
import type { TeamDocumentFields } from '../models/team.model';
import type TeamsRepository from '../repositories/teams.repository';

class TeamsService {
	constructor(private teamsRepository: TeamsRepository) {}

	public getMarbleTeam(
		marble: MarbleDocumentFields
	): Promise<TeamDocumentFields | null> {
		return this.teamsRepository.getOne(marble.team);
	}

	public getOne(name: string) {
		return this.teamsRepository.getOne(name);
	}

	public getAll() {
		return this.teamsRepository.getAll();
	}
}

export default TeamsService;
