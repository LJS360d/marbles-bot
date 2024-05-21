import type {
	MarbleCollectionDocument,
	MarbleCollectionDocumentFields,
} from '../models/collection.model';
import type CollectionsRepository from '../repositories/collections.repository';

class CollectionsService {
	constructor(private collectionsRepository: CollectionsRepository) {}

	public getOneRandom() {
		return this.collectionsRepository.getOneRandom();
	}

	public getOne(guildId: string, userId: string) {
		return this.collectionsRepository.getOneByGuildIdAndUserId(guildId, userId);
	}

	public getAll() {
		return this.collectionsRepository.getAll();
	}

	public addMarble(guildId: string, userId: string, marbleName: string) {
		return this.collectionsRepository.addMarble(guildId, userId, marbleName);
	}

	public create(obj: MarbleCollectionDocumentFields) {
		return this.collectionsRepository.create(obj as MarbleCollectionDocument);
	}
}

export default CollectionsService;
