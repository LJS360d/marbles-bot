import { type Model, type Document, type UpdateQuery, now } from 'mongoose';

export class NameBaseRepository<T extends Document> {
	public entity!: Model<T>;

	async getOne(name: string): Promise<T | null> {
		return await this.entity.findOne({ name }).exec();
	}

	async getAll(): Promise<T[]> {
		return await this.entity.find().exec();
	}

	async create(fields: T): Promise<T> {
		return await this.entity.create({ updatedAt: now(), ...fields });
	}

	async update(name: string, fields: UpdateQuery<T>) {
		return await this.entity
			.updateOne({ name }, { updatedAt: now(), ...fields }, { new: true })
			.exec();
	}

	async delete(name: string) {
		return await this.entity.deleteOne({ name }).exec();
	}
}
