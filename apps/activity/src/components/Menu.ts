import { TextButton } from './TextButton';

export class Menu extends Phaser.GameObjects.Container {
	private menuItems: TextButton[];
	private currentIndex: number | null;
	private keys: {
		up: Phaser.Input.Keyboard.Key;
		down: Phaser.Input.Keyboard.Key;
		left: Phaser.Input.Keyboard.Key;
		right: Phaser.Input.Keyboard.Key;
		select: Phaser.Input.Keyboard.Key;
		esc: Phaser.Input.Keyboard.Key;
	};

	constructor(
		scene: Phaser.Scene,
		items: { text: string; callback: () => void }[],
		x: number,
		y: number,
		style?: Phaser.Types.GameObjects.Text.TextStyle
	) {
		super(scene, x, y);
		scene.add.existing(this);

		this.menuItems = items.map((item, index) => {
			const menuItem = new TextButton(scene, {
				x: 0,
				y: index * 40,
				onClick: item.callback,
				text: item.text,
				style,
			});
			this.add(menuItem);
			return menuItem;
		});

		this.currentIndex = 0;

		if (!scene.input.keyboard) return;
		this.keys = {
			up: scene.input.keyboard.addKey(Phaser.Input.Keyboard.KeyCodes.UP),
			down: scene.input.keyboard.addKey(Phaser.Input.Keyboard.KeyCodes.DOWN),
			left: scene.input.keyboard.addKey(Phaser.Input.Keyboard.KeyCodes.LEFT),
			right: scene.input.keyboard.addKey(Phaser.Input.Keyboard.KeyCodes.RIGHT),
			select: scene.input.keyboard.addKey(Phaser.Input.Keyboard.KeyCodes.ENTER),
			esc: scene.input.keyboard.addKey(Phaser.Input.Keyboard.KeyCodes.ESC),
		};

		this.updateSelection();
	}

	private updateSelection() {
		this.menuItems.forEach((item, index) => {
			if (index === this.currentIndex) {
				item.onHover();
			} else {
				item.onOut();
			}
		});
	}

	private selectItem() {
		const item = this.menuItems.at(this.currentIndex ?? 0);
		item?.emit('pointerdown');
	}
	update(): void {
		if (Phaser.Input.Keyboard.JustDown(this.keys.esc)) {
			this.currentIndex = null;
			this.updateSelection();
		}
		if (Phaser.Input.Keyboard.JustDown(this.keys.up)) {
			this.currentIndex =
				((this.currentIndex ?? 0) - 1 + this.menuItems.length) %
				this.menuItems.length;
			this.updateSelection();
		}

		if (Phaser.Input.Keyboard.JustDown(this.keys.down)) {
			this.currentIndex =
				((this.currentIndex ?? 0) + 1) % this.menuItems.length;
			this.updateSelection();
		}

		if (Phaser.Input.Keyboard.JustDown(this.keys.select)) {
			this.selectItem();
		}
	}
}
