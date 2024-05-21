import sharp from 'sharp';
import fs from 'node:fs';
import path from 'node:path';

const TARGET_WIDTH = 240; // Set your target width
const TARGET_HEIGHT = 240; // Set your target height
const ASSETS_DIR = path.join(__dirname, '../public/assets'); // Adjust this path as needed

const resizeImage = async (filePath: string) => {
	const outputDir = path.join(path.dirname(filePath), 'resized');
	const outputFilePath = path
		.join(outputDir, path.basename(filePath))
		.replace('.jpg', '.png');

	// Ensure the output directory exists
	fs.mkdirSync(outputDir, { recursive: true });

	try {
		await sharp(filePath)
			.resize(TARGET_WIDTH, TARGET_HEIGHT, {
				fit: 'contain',
				background: { r: 0, g: 0, b: 0, alpha: 0 },
			})
			.toFile(outputFilePath);
		console.log(`Resized and saved: ${outputFilePath}`);
	} catch (err) {
		console.error(`Error resizing image ${filePath}:`, err);
	}
};

const processDirectory = (dir: string) => {
	fs.readdir(dir, (err, files) => {
		if (err) {
			console.error(`Error reading directory ${dir}:`, err);
			return;
		}

		files.forEach((file) => {
			const filePath = path.join(dir, file);
			fs.stat(filePath, (err, stats) => {
				if (err) {
					console.error(`Error getting stats for file ${filePath}:`, err);
					return;
				}

				if (stats.isDirectory()) {
					processDirectory(filePath);
				} else if (stats.isFile() && /\.(jpe?g|png)$/i.test(file)) {
					resizeImage(filePath);
				}
			});
		});
	});
};

// Start processing
processDirectory(ASSETS_DIR);
