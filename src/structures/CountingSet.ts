export class CountingSet<T> extends Set<T> {
    protected countMap: Map<T, number>;

    constructor() {
        super();
        this.countMap = new Map<T, number>();
    }

    add(value: T): this {
        super.add(value);
        const count = this.countMap.get(value) ?? 0;
        this.countMap.set(value, count + 1);
        return this;
    }
    getValue(key: T): number {
        return this.countMap.get(key) || 0;
    }
    protected setValue(key: T, value: number) {
        this.countMap.set(key, value);
    }


}