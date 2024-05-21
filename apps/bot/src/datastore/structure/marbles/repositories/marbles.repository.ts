import { NameBaseRepository } from '../../../database/common/name.base.repository';
import {
	MarbleModel,
	type MarbleDocument,
	type MarbleDocumentFields,
} from '../models/marble.model';

class MarblesRepository extends NameBaseRepository<MarbleDocument> {
	public entity = MarbleModel;

	public async getOneRandom(): Promise<MarbleDocumentFields> {
		return (await this.entity.aggregate([{ $sample: { size: 1 } }]).exec()).at(
			0
		) as MarbleDocumentFields;
	}
}

export default MarblesRepository;
