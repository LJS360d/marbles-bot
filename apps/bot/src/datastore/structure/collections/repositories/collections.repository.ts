import { Logger } from 'fonzi2';
import { BaseRepository } from '../../../database/common/base.repository';
import CountingSet from '../../counting.set';
import {
	MarbleCollectionModel,
	type MarbleCollectionDocument,
	type MarbleCollectionDocumentFields,
} from '../models/collection.model';

class CollectionsRepository extends BaseRepository<MarbleCollectionDocument> {
	public entity = MarbleCollectionModel;

	public async getOneRandom() {
		try {
			return (
				await this.entity.aggregate([{ $sample: { size: 1 } }]).exec()
			).at(0) as MarbleCollectionDocumentFields;
		} catch (error) {
			console.error(error);
			return null;
		}
	}

	public async getOneByGuildIdAndUserId(
		guildId: string,
		userId: string
	): Promise<MarbleCollectionDocument | null> {
		try {
			const collection = await this.entity.findOne({ guildId, userId });
			if (!collection) {
				Logger.info(`Creating collection for ${guildId}-${userId}`);
				const newCollection = new this.entity({
					guildId,
					userId,
					marbles: [],
				});
				return newCollection.save();
			}
			return collection;
		} catch (error) {
			console.error(error);
			return null;
		}
	}

	public async addMarble(guildId: string, userId: string, marble: string) {
		try {
			const collection = await this.getOneByGuildIdAndUserId(guildId, userId);
			if (collection === null) {
				Logger.info(`Creating collection for ${guildId}-${userId}`);
				const newCollection = new this.entity({
					guildId,
					userId,
					marbles: [[marble, 1]],
				});
				return newCollection.save();
			}
			const set = CountingSet.fromJson(collection.marbles);
			set.add(marble);
			return await this.entity.updateOne(
				{
					_id: collection._id,
				},
				{
					guildId,
					userId,
					marbles: set.toJson(),
				}
			);
		} catch (error) {
			console.error(error);
			return null;
		}
	}
}

export default CollectionsRepository;
