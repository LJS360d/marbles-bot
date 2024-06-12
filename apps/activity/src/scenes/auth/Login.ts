import { Scene } from 'phaser';
import { Theme } from '../../theme';
import { TextButton } from '../../components/TextButton';

export class Login extends Scene {
  constructor() {
    super('Login');
  }

  create() {
    const dialog = this.rexUI.add
      .dialog({
        x: Number(this.game.config.width) * 0.5,
        y: Number(this.game.config.height) * 0.5,
        background: this.rexUI.add.roundRectangle(0, 0, 100, 100, 20, 0x1565c0),
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
          align: 'top',
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
            }),
            new TextButton(this, {
              text: 'Login with Discord',
              x: 0,
              y: 0,
              onClick: () => {
                console.log('Login with Discord');
                this.scene.start('MainMenu');
              },
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
