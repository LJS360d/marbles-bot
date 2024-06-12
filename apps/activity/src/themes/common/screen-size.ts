/**
 * Enumeration of Bootstrap's responsive breakpoints.
 *
 * These breakpoints define the pixel widths at which layouts
 * and components adjust their display to suit different screen sizes.
 *
 * - **xs**: Extra small devices (portrait phones), less than 576px
 * - **sm**: Small devices (landscape phones), less than768px
 * - **md**: Medium devices (tablets), less than 992px
 * - **lg**: Large devices (desktops), less than 1200px
 * - **xl**: Extra large devices (large desktops), less than 1400px
 * - **xxl**: Extra extra large devices (over scale), 1400px and up
 *
 * @enum {number}
 */
export enum ScreenSize {
  xs = 576,
  sm = 768,
  md = 992,
  lg = 1200,
  xl = 1400,
  // 32 bit integer limit
  xxl = 2.147483647e9,
}
