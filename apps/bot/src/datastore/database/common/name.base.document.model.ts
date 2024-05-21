import { Document } from 'mongoose';

export class NameBaseDocument extends Document {
	declare name: string;
	updatedAt!: NativeDate;
}
