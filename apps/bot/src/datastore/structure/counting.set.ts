export type CountingSetConstructor<T> = [T, number];

class CountingSet<T> extends Set<T> {
	protected countMap: Map<T, number>;

	constructor() {
		super();
		this.countMap = new Map<T, number>();
	}

	static fromJson<T>(json: CountingSetConstructor<T>[]) {
		const set = new CountingSet<T>();
		json.forEach((cons) => {
			set.setCount(cons.at(0) as T, Number(cons.at(1)));
		});
		return set;
	}

	toJson(): CountingSetConstructor<T>[] {
		return Array.from(this.countMap.entries());
	}

	override add(value: T): this {
		super.add(value);
		const count = this.getCount(value) ?? 0;
		this.countMap.set(value, count + 1);
		return this;
	}

	getCount(key: T): number | undefined {
		return this.countMap.get(key);
	}

	setCount(key: T, count: number): this {
		super.add(key);
		this.countMap.set(key, count);
		return this;
	}
}

export default CountingSet;
