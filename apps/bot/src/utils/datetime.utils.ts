const FIFTEEN_MINUTES_IN_MS = 15 * 60 * 1000;
export function areTimestampsAtLeast15MinutesApart(
	t1: number,
	t2: number
): boolean {
	return t2 - t1 >= FIFTEEN_MINUTES_IN_MS;
}
