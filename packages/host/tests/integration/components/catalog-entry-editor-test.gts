import { module, test } from 'qunit';
import GlimmerComponent from '@glimmer/component';
import { baseRealm, ExportedCardRef } from '@cardstack/runtime-common';
import { Loader } from "@cardstack/runtime-common/loader";
import { Realm } from "@cardstack/runtime-common/realm";
import { setupRenderingTest } from 'ember-qunit';
import { renderComponent } from '../../helpers/render-component';
import CatalogEntryEditor from '@cardstack/host/components/catalog-entry-editor';
import Service from '@ember/service';
import { TestRealm, TestRealmAdapter, testRealmURL } from '../../helpers';
import waitUntil from '@ember/test-helpers/wait-until';
import { waitFor, fillIn, click } from '../../helpers/shadow-assert';
import type LoaderService from '@cardstack/host/services/loader-service';

class MockLocalRealm extends Service {
  isAvailable = true;
  url = new URL(testRealmURL);
}

module('Integration | catalog-entry-editor', function (hooks) {
  let adapter: TestRealmAdapter
  let realm: Realm;
  setupRenderingTest(hooks);

  hooks.beforeEach(async function() {
    // this seeds the loader used during index which obtains url mappings
    // from the global loader
    Loader.addURLMapping(
      new URL(baseRealm.url),
      new URL('http://localhost:4201/base/')
    );
    adapter = new TestRealmAdapter({});
    realm = TestRealm.createWithAdapter(adapter);
    let loader = (this.owner.lookup('service:loader-service') as LoaderService).loader;
    loader.registerURLHandler(new URL(realm.url), realm.handle.bind(realm));
    await realm.ready;

    await realm.write('person.gts', `
      import { contains, field, Component, Card } from "https://cardstack.com/base/card-api";
      import StringCard from "https://cardstack.com/base/string";
      export class Person extends Card {
        @field firstName = contains(StringCard);
        static embedded = class Embedded extends Component<typeof this> {
          <template><@fields.firstName/></template>
        }
      }
    `);

    await realm.write('pet.gts', `
      import { contains, field, Component, Card } from "https://cardstack.com/base/card-api";
      import StringCard from "https://cardstack.com/base/string";
      import BooleanCard from "https://cardstack.com/base/boolean";
      import DateCard from "https://cardstack.com/base/date";
      import { Person } from "./person";
      export class Pet extends Card {
        @field name = contains(StringCard);
        @field lovesWalks = contains(BooleanCard);
        @field birthday = contains(DateCard);
        @field owner = contains(Person);
        static embedded = class Embedded extends Component<typeof this> {
          <template>
            <h2 data-test-pet-name><@fields.name/></h2>
            <div data-test-pet-owner><@fields.owner/></div>
            <div data-test-pet-owner><@fields.birthday/></div>
          </template>
        }
      }
    `);

    this.owner.register('service:local-realm', MockLocalRealm);
  });

  hooks.afterEach(function() {
    Loader.destroy();
  });

  test('can publish new catalog entry', async function (assert) {
    const args: ExportedCardRef =  { module: `${testRealmURL}pet`, name: 'Pet' };
    await renderComponent(
      class TestDriver extends GlimmerComponent {
        <template>
          <CatalogEntryEditor @ref={{args}} />
        </template>
      }
    );

    await waitFor('button[data-test-catalog-entry-publish]');
    await click('[data-test-catalog-entry-publish]');
    await waitFor('[data-test-ref]');

    assert.shadowDOM('[data-test-catalog-entry-editor] [data-test-field="title"] input').hasValue('Pet');
    assert.shadowDOM('[data-test-catalog-entry-editor] [data-test-field="description"] input').hasValue('Catalog entry for Pet card');
    assert.shadowDOM('[data-test-ref]').exists();
    assert.shadowDOM('[data-test-ref]').containsText(`Module: ${testRealmURL}pet Name: Pet`);
    assert.shadowDOM('[data-test-field="demo"] [data-test-field="name"] input').hasText('');
    assert.shadowDOM('[data-test-field="demo"] [data-test-field="lovesWalks"] label:nth-of-type(2) input').isChecked();

    await fillIn('[data-test-field="title"] input', 'Pet test');
    await fillIn('[data-test-field="description"] input', 'Test description');
    await fillIn('[data-test-field="name"] input', 'Jackie');
    await click('[data-test-field="lovesWalks"] label:nth-of-type(1) input');
    await fillIn('[data-test-field="firstName"] input', 'BN');
    await click('button[data-test-save-card]');

    await waitUntil(() => !(document.querySelector('[data-test-saving]')));

    let entry = await realm.searchIndex.card(new URL(`${testRealmURL}CatalogEntry/1`));
    assert.ok(entry, 'the new catalog entry was created');

    let fileRef = await adapter.openFile('CatalogEntry/1.json');
    if (!fileRef) {
      throw new Error('file not found');
    }
    assert.deepEqual(
      JSON.parse(fileRef.content as string),
      {
        data: {
          type: 'card',
          attributes: {
            title: 'Pet test',
            description: 'Test description',
            ref: {
              module: `${testRealmURL}pet`,
              name: 'Pet'
            },
            demo: {
              name: 'Jackie',
              lovesWalks: true,
              birthday: null,
              owner: {
                firstName: 'BN'
              }
            },
          },
          meta: {
            adoptsFrom: {
              module: 'https://cardstack.com/base/catalog-entry',
              name: 'CatalogEntry',
            },
            fields: {
              demo: {
                adoptsFrom: {
                  module: `${testRealmURL}pet`,
                  name: 'Pet',
                }
              }
            }
          },
        },
      },
      'file contents are correct'
    );
  });

  test('can edit existing catalog entry', async function (assert) {
    await realm.write('pet-catalog-entry.json', JSON.stringify({
      data: {
        type: 'card',
        attributes: {
          title: 'Pet',
          description: 'Catalog entry',
          ref: {
            module: `${testRealmURL}pet`,
            name: 'Pet'
          },
          demo: {
            name: 'Jackie',
            lovesWalks: true,
            birthday: null,
            owner: {
              firstName: 'BN'
            }
          }
        },
        meta: {
          adoptsFrom: {
            module:`${baseRealm.url}catalog-entry`,
            name: 'CatalogEntry'
          },
          fields: {
            demo: {
              adoptsFrom: {
                module: `${testRealmURL}pet`,
                name: 'Pet',
              }
            }
          }
        }
      }
    }));

    const args: ExportedCardRef =  { module: `${testRealmURL}pet`, name: 'Pet' };
    await renderComponent(
      class TestDriver extends GlimmerComponent {
        <template>
          <CatalogEntryEditor @ref={{args}} />
        </template>
      }
    );

    await waitFor('[data-test-ref]');
    await click('[data-test-format-button="edit"]');

    assert.dom('[data-test-catalog-entry-id]').hasText(`${testRealmURL}pet-catalog-entry`);
    assert.shadowDOM('[data-test-catalog-entry-editor] [data-test-field="title"] input').hasValue('Pet');
    assert.shadowDOM('[data-test-catalog-entry-editor] [data-test-field="description"] input').hasValue('Catalog entry');
    assert.shadowDOM('[data-test-ref]').exists();
    assert.shadowDOM('[data-test-ref]').containsText(`Module: ${testRealmURL}pet Name: Pet`);
    assert.shadowDOM('[data-test-field="demo"] [data-test-field="name"] input').hasValue('Jackie');
    assert.shadowDOM('[data-test-field="demo"] [data-test-field="lovesWalks"] label:nth-of-type(1) input').isChecked();
    assert.shadowDOM('[data-test-field="demo"] [data-test-field="owner"] [data-test-field="firstName"] input').hasValue('BN');

    await fillIn('[data-test-field="title"] input', 'test title');
    await fillIn('[data-test-field="description"] input', 'test description');
    await fillIn('[data-test-field="name"] input', 'Jackie Wackie');
    await fillIn('[data-test-field="firstName"] input', 'EA');

    await click('button[data-test-save-card]');
    await waitUntil(() => !(document.querySelector('[data-test-saving]')));

    assert.shadowDOM('[data-test-title]').hasText('test title');
    assert.shadowDOM('[data-test-description]').hasText('test description');
    assert.shadowDOM('[data-test-demo] [data-test-pet-name]').hasText('Jackie Wackie');
    assert.shadowDOM('[data-test-demo] [data-test-pet-owner]').hasText('EA');

    let maybeError = await realm.searchIndex.card(new URL(`${testRealmURL}pet-catalog-entry`));
    if (maybeError?.type === 'error') {
      throw new Error(
        `unexpected error when getting card from index: ${maybeError.error.detail}`
      );
    }
    let { doc } = maybeError!;
    assert.strictEqual(doc?.data.attributes?.title, 'test title', 'catalog entry title was updated');
    assert.strictEqual(doc?.data.attributes?.description, 'test description', 'catalog entry description was updated');
    assert.strictEqual(doc?.data.attributes?.demo?.name, 'Jackie Wackie', 'demo name field was updated');
    assert.strictEqual(doc?.data.attributes?.demo?.owner?.firstName, 'EA', 'demo owner firstName field was updated');
  });

  test('can create new card with missing composite field value', async function (assert) {
    const args: ExportedCardRef =  { module: `${testRealmURL}pet`, name: 'Pet' };
    await renderComponent(
      class TestDriver extends GlimmerComponent {
        <template>
          <CatalogEntryEditor @ref={{args}} />
        </template>
      }
    );

    await waitFor('button[data-test-catalog-entry-publish]');
    await click('[data-test-catalog-entry-publish]');
    await waitFor('[data-test-ref]');

    await fillIn('[data-test-field="name"] input', 'Jackie');
    await click('button[data-test-save-card]');
    await waitUntil(() => !(document.querySelector('[data-test-saving]')));

    let entry = await realm.searchIndex.card(new URL(`${testRealmURL}CatalogEntry/1`));
    assert.ok(entry, 'catalog entry was created');

    await renderComponent(
      class TestDriver extends GlimmerComponent {
        <template>
          <CatalogEntryEditor @ref={{args}} />
        </template>
      }
    );

    await waitFor('[data-test-ref]');
    await click('[data-test-format-button="edit"]');
    await assert.shadowDOM('[data-test-field="firstName"] input').exists();

    let fileRef = await adapter.openFile('CatalogEntry/1.json');
    if (!fileRef) {
      throw new Error('file not found');
    }
    assert.deepEqual(
      JSON.parse(fileRef.content as string),
      {
        data: {
          type: 'card',
          attributes: {
            title: 'Pet',
            description: 'Catalog entry for Pet card',
            ref: {
              module: `${testRealmURL}pet`,
              name: 'Pet'
            },
            demo: {
              name: 'Jackie',
              lovesWalks: false,
              birthday: null,
              owner: {
                firstName: null
              }
            },
          },
          meta: {
            adoptsFrom: {
              module: 'https://cardstack.com/base/catalog-entry',
              name: 'CatalogEntry',
            },
            fields: {
              demo: {
                adoptsFrom: {
                  module: `${testRealmURL}pet`,
                  name: 'Pet',
                }
              },
            }
          },
        },
      },
      'file contents are correct'
    );
  });

  test('can create new catalog entry with all demo card field values missing', async function (assert) {
    const args: ExportedCardRef =  { module: `${testRealmURL}person`, name: 'Person' };
    await renderComponent(
      class TestDriver extends GlimmerComponent {
        <template>
          <CatalogEntryEditor @ref={{args}} />
        </template>
      }
    );

    await waitFor('button[data-test-catalog-entry-publish]');
    await click('[data-test-catalog-entry-publish]');
    await waitFor('[data-test-ref]');

    await click('button[data-test-save-card]');
    await waitUntil(() => !(document.querySelector('[data-test-saving]')));

    await renderComponent(
      class TestDriver extends GlimmerComponent {
        <template>
          <CatalogEntryEditor @ref={{args}} />
        </template>
      }
    );

    await waitFor('[data-test-ref]');
    await click('[data-test-format-button="edit"]');
    assert.shadowDOM('[data-test-field="firstName"] input').exists();

    let entry = await realm.searchIndex.card(new URL(`${testRealmURL}CatalogEntry/1`));
    assert.ok(entry, 'catalog entry was created');

    let fileRef = await adapter.openFile('CatalogEntry/1.json');
    if (!fileRef) {
      throw new Error('file not found');
    }
    assert.deepEqual(
      JSON.parse(fileRef.content as string),
      {
        data: {
          type: 'card',
          attributes: {
            demo: {
              firstName: null,
            },
            title: 'Person',
            description: 'Catalog entry for Person card',
            ref: {
              module: `${testRealmURL}person`,
              name: 'Person'
            },
          },
          meta: {
            adoptsFrom: {
              module: 'https://cardstack.com/base/catalog-entry',
              name: 'CatalogEntry',
            },
            fields: {
              demo: {
                adoptsFrom: {
                  module: `${testRealmURL}person`,
                  name: 'Person',
                }
              },
            }
          },
        },
      },
      'file contents are correct'
    );
  });

  test('it can render catalog entry for card with linksTo field', async function (assert) {
    await realm.write('pet.gts', `
      import { contains, field, Card, Component } from "https://cardstack.com/base/card-api";
      import StringCard from "https://cardstack.com/base/string";
      export class Pet extends Card {
        @field name = contains(StringCard);
        static embedded = class Embedded extends Component<typeof this> {
          <template><h4 data-test-pet-name><@fields.name/></h4></template>
        };
      }
    `);
    await realm.write('person.gts', `
      import { contains, field, linksTo, Card, Component } from "https://cardstack.com/base/card-api";
      import StringCard from "https://cardstack.com/base/string";
      import { Pet } from "./pet";
      export class Person extends Card {
        @field firstName = contains(StringCard);
        @field lastName = contains(StringCard);
        @field pet = linksTo(Pet);
        static embedded = class Embedded extends Component<typeof this> {
          <template>
            <h3 data-test-person-name><@fields.firstName/> <@fields.lastName/></h3>
            <div>Pet: <@fields.pet/></div>
          </template>
        };
      }
    `);
    await realm.write('jackie-pet.json', JSON.stringify({
      data: {
        type: 'card',
        attributes: {
          name: 'Jackie',
        },
        meta: {
          adoptsFrom: {
            module:`${testRealmURL}pet`,
            name: 'Pet'
          }
        }
      }
    }));
    await realm.write('person-entry.json', JSON.stringify({
      data: {
        type: 'card',
        attributes: {
          title: 'Person',
          description: 'Catalog entry',
          ref: {
            module: `${testRealmURL}person`,
            name: 'Person'
          },
          demo: {
            firstName: 'Burcu',
            lastName: 'Noyan'
          }
        },
        relationships: {
          "demo.pet": {
            links: {
              self: `${testRealmURL}jackie-pet`
            }
          }
        },
        meta: {
          fields: {
            demo: {
              adoptsFrom: {
                module: `${testRealmURL}person`,
                name: "Person"
              }
            }
          },
          adoptsFrom: {
            module:`${baseRealm.url}catalog-entry`,
            name: 'CatalogEntry'
          }
        }
      }
    }));

    const args: ExportedCardRef =  { module: `${testRealmURL}person`, name: 'Person' };
    await renderComponent(
      class TestDriver extends GlimmerComponent {
        <template>
          <CatalogEntryEditor @ref={{args}}/>
        </template>
      }
    );

    await waitFor('[data-test-ref]');
    assert.shadowDOM(`[data-test-ref]`).hasText(`Module: ${testRealmURL}person Name: Person`);

    await waitFor('[data-test-person-name]');
    assert.shadowDOM('[data-test-person-name]').hasText('Burcu Noyan');

    await waitFor('[data-test-pet-name]');
    assert.shadowDOM('[data-test-pet-name]').hasText('Jackie');
  });
});
