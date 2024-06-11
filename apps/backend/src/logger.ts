import { createLogger, format, transports } from 'winston';
const { combine, timestamp, printf, colorize, align } = format;

const logger = createLogger({
  format: combine(
    format((info) => {
      info.level = info.level.trim().toUpperCase();
      return info;
    })(),
    colorize({ level: true, message: false }),
    timestamp({
      format: 'DD/MM/YYYY, HH:mm:ss',
    }),
    align(),
    printf(
      (info) => `${CC.gray}[${info.timestamp}] ${info.level}${info.message}`
    )
  ),
  transports: [
    new transports.Console(),
    new transports.File({ filename: 'logs/error.log', level: 'error' }),
  ],
});

export default logger;

export enum CC {
  stop = '\x1b[0m',
  bold = '\x1b[1m',
  italic = '\x1b[3m',
  underline = '\x1b[4m',
  highlight = '\x1b[7m',
  hidden = '\x1b[8m',
  strikethrough = '\x1b[9m',
  doubleUnderline = '\x1b[21m',
  black = '\x1b[30m',
  gray = '\x1b[37m',
  red = '\x1b[31m',
  green = '\x1b[32m',
  yellow = '\x1b[33m',
  blue = '\x1b[34m',
  magenta = '\x1b[35m',
  cyan = '\x1b[36m',
  white = '\x1b[38m',
  blackbg = '\x1b[40m',
  redbg = '\x1b[41m',
  greenbg = '\x1b[42m',
  yellowbg = '\x1b[43m',
  bluebg = '\x1b[44m',
  magentabg = '\x1b[45m',
  cyanbg = '\x1b[46m',
  whitebg = '\x1b[47m',
}
