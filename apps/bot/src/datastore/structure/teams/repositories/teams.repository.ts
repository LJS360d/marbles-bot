import { NameBaseRepository } from '../../../database/common/name.base.repository';
import { TeamModel, type TeamDocument } from '../models/team.model';

class TeamsRepository extends NameBaseRepository<TeamDocument> {
	public entity = TeamModel;
}

export default TeamsRepository;
