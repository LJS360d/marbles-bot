import type {
	MarbleDocument,
	MarbleDocumentFields,
} from '../models/marble.model';
import type MarblesRepository from '../repositories/marbles.repository';

class MarblesService {
	constructor(private marblesRepository: MarblesRepository) {}

	public getOneRandom() {
		return this.marblesRepository.getOneRandom();
	}

	public getOne(name: string) {
		return this.marblesRepository.getOne(name);
	}

	public getAll() {
		return this.marblesRepository.getAll();
	}

	public create(obj: MarbleDocumentFields) {
		return this.marblesRepository.create(obj as MarbleDocument);
	}
}

export default MarblesService;
