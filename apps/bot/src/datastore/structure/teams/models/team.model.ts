import { Schema, model, type Document } from 'mongoose';

/* model: Team */
export interface TeamDocumentFields {
	name: string;
	color: string;
	coach: string;
	manager: string;
	members: string[];
	logo: string;
}

export type TeamDocument = TeamDocumentFields & Document<string, any, any>;

export const TeamSchema = new Schema<TeamDocument>({
	name: { type: String, required: true, unique: true },
	color: { type: String },
	coach: { type: String },
	manager: { type: String },
	members: { type: [String] },
	logo: { type: String },
});

export const TeamModel = model<TeamDocument>('teams', TeamSchema);
