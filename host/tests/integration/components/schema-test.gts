import { module, test } from 'qunit';
import GlimmerComponent from '@glimmer/component';
import { CardRef } from '@cardstack/runtime-common';
import { setupRenderingTest } from 'ember-qunit';
import { renderComponent } from '../../helpers/render-component';
import Schema from 'runtime-spike/components/schema';
import Service from '@ember/service';
//@ts-ignore no types (double check that)
import { setupMirage } from 'ember-cli-mirage/test-support';
import { waitUntil } from '@ember/test-helpers';

class MockLocalRealm extends Service {
  isAvailable = true;
  url = new URL('http://test-realm/');
}

module('Integration | schema', function (hooks) {
  setupRenderingTest(hooks);
  setupMirage(hooks);

  hooks.beforeEach(function() {
    this.owner.register('service:local-realm', MockLocalRealm);
  })

  test('renders card schema view', async function (assert) {
    const args: CardRef =  { type: 'exportedCard', module: 'http://test-realm/person', name: 'Person' };
    await renderComponent(
      class TestDriver extends GlimmerComponent {
        <template>
          <Schema @ref={{args}} />
        </template>
      }
    );

    await waitUntil(() => Boolean(document.querySelector('[data-test-card-id]')));

    assert.dom('[data-test-card-id]').hasText('Card ID: http://test-realm/person/Person');
    assert.dom('[data-test-adopts-from').hasText('Adopts From: https://cardstack.com/base/card-api/Card');
    assert.dom('[data-test-field="firstName"]').hasText('firstName - contains - field card ID: https://cardstack.com/base/string/default');
  });
});