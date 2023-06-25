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
    getValue(value: T): number {
        return this.countMap.get(value) || 0;
    }

    
}