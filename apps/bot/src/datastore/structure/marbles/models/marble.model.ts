import { Schema, model, type Document } from 'mongoose';
/* model: Marble */
export interface MarbleDocumentFields {
	name: string;
	team: string;
	image: string;
	color: string;
	position: string;
	competition: string;
	extra: string;
}

export type MarbleDocument = MarbleDocumentFields & Document<string, any, any>;

const MarbleSchema = new Schema<MarbleDocument>(
	{
		name: { type: String, required: true, unique: true },
		team: { type: String, ref: 'teams.name' },
		image: { type: String },
		color: { type: String },
		position: { type: String, required: true },
		competition: { type: String },
	},
	{
		autoIndex: true,
	}
);

export const MarbleModel = model<MarbleDocument>('marbles', MarbleSchema);
