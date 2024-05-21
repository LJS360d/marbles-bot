import { Schema, model, type Document } from 'mongoose';
import type { CountingSetConstructor } from '../../counting.set';
/* model: MarbleCollection */
export interface MarbleCollectionDocumentFields {
	guildId: string;
	userId: string;
	marbles: CountingSetConstructor<string>[];
}

export type MarbleCollectionDocument = MarbleCollectionDocumentFields &
	Document<string, any, any>;

const MarbleCollectionSchema = new Schema<MarbleCollectionDocument>(
	{
		guildId: { type: String, required: true },
		userId: { type: String, required: true },
		marbles: { type: [[String, Number]], default: [] },
	},
	{
		autoIndex: true,
	}
);

export const MarbleCollectionModel = model<MarbleCollectionDocument>(
	'collections',
	MarbleCollectionSchema
);
