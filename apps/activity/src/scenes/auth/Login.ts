import { Scene } from 'phaser';
import { Theme } from '../../theme';
import { TextButton } from '../../components/TextButton';

export class Login extends Scene {
  constructor() {
    super('Login');
  }

  create() {
    const bg = this.add.image(
      this.cameras.main.width / 2,
      this.cameras.main.height / 2,
      'background'
    );
    const scaleX = this.cameras.main.width / bg.width + 0.2;
    const scaleY = this.cameras.main.height / bg.height + 0.2;
    const scale = Math.max(scaleX, scaleY);
    bg.setScale(scale).setScrollFactor(0);
    const dialog = this.rexUI.add
      .dialog({
        x: Number(this.game.config.width) * 0.5,
        y: Number(this.game.config.height) * 0.5,
        background: this.rexUI.add.roundRectangle(
          0,
          0,
          100,
          100,
          20,
          Theme.hexColors.transparent
        ),
        title: this.rexUI.add.label({
          text: this.add.text(0, 0, 'Wait, who are you?', Theme.text.headline),
        }),
        content: this.rexUI.add.buttons({
          x: 0,
          y: 0,
          space: {
            left: 15,
            right: 15,
            top: 10,
            bottom: 10,
          },
          align: 'left',
          orientation: 'vertical',
          setValueCallback: (value) => {
            console.log(value);
          },
          buttons: [
            new TextButton(this, {
              text: 'Enter as a guest',
              x: 0,
              y: 0,
              onClick: () => {
                console.log('Enter as a guest');
                this.scene.start('MainMenu');
              },
              style: Theme.button.success,
            }),
            new TextButton(this, {
              text: 'Login with Discord',
              x: 0,
              y: 0,
              onClick: () => {
                window.open('/api/login/discord', '_self');
              },
              style: Theme.button.ghost,
            }),
          ],
        }),

        space: {
          title: 25,
          content: 25,
          action: 15,

          left: 20,
          right: 20,
          top: 20,
          bottom: 20,
        },

        align: {
          actions: 'center',
        },

        expand: {
          actions: true,
          content: false,
        },
      })
      .layout()
      .popUp(1000);

    dialog
      .on(
        'button.click',
        function (button, groupName, index) {
          this.print.text += `${index}: ${button.text}\n`;
        },
        this
      )
      .on('button.over', (button, groupName, index) => {
        button.getElement('background').setStrokeStyle(1, 0xffffff);
      })
      .on('button.out', (button, groupName, index) => {
        button.getElement('background').setStrokeStyle();
      });
  }
}
