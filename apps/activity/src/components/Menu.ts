import { TextButton } from './TextButton';

export class Menu extends Phaser.GameObjects.Container {
  private menuItems: TextButton[];
  private currentIndex: number | null;
  private arrow: Phaser.GameObjects.Text;
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
    style?: Phaser.Types.GameObjects.Text.TextStyle,
    arrowStyle: Phaser.Types.GameObjects.Text.TextStyle = {
      fontSize: 38,
      color: '#ffffff',
    }
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
    this.arrow = scene.add
      .text(this.x, this.y, '>', arrowStyle)
      .setVisible(false);

    this.updateSelection();
  }

  private updateSelection() {
    this.arrow.setVisible(this.currentIndex !== null);
    this.menuItems.forEach((item, index) => {
      if (index === this.currentIndex) {
        item.onHover();
        const bounds = item.getBounds();
        this.arrow.setPosition(
          bounds.left - this.arrow.width - 10,
          bounds.top + bounds.height / 2 - this.arrow.height / 2
        );
      } else {
        item.onOut();
      }
    });
  }

  private selectItem() {
    const item = this.menuItems.at(this.currentIndex ?? 0);
    item?.emit('pointerdown');
    setTimeout(() => item?.emit('pointerup'), 100);
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
