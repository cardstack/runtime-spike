import Service from '@ember/service';
import { tracked } from '@glimmer/tracking';
import { action } from '@ember/object';

export default class Modal extends Service {
  @tracked state: 'open' | 'closed' = 'closed';

  get isShowing(): boolean {
    return this.state === 'open';
  }

  @action open(): void {
    this.state = 'open';
  }

  @action close(): void {
    this.state = 'closed';
  }
}
