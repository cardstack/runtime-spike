import { module, test } from 'qunit';
import { TestContext } from '@ember/test-helpers';
import GlimmerComponent from '@glimmer/component';
import { ExportedCardRef } from '@cardstack/runtime-common';
import { setupRenderingTest } from 'ember-qunit';
import { renderComponent } from '../../helpers/render-component';
import Schema from 'runtime-spike/components/schema';
import { file, FileResource } from 'runtime-spike/resources/file';
import { ModuleSyntax } from '@cardstack/runtime-common/module-syntax';
import Service from '@ember/service';
import { waitFor, click, fillIn } from '@ember/test-helpers';
import { Loader } from '@cardstack/runtime-common/loader';
import { baseRealm } from '@cardstack/runtime-common';
import { RealmPaths } from '@cardstack/runtime-common/paths';
import { TestRealm, TestRealmAdapter, testRealmURL } from '../../helpers';
import { Realm } from "@cardstack/runtime-common/realm";
import CardCatalogModal from 'runtime-spike/components/card-catalog-modal';
import "@cardstack/runtime-common/helpers/code-equality-assertion";

class MockLocalRealm extends Service {
  isAvailable = true;
  url = new URL(testRealmURL);
}

module('Integration | schema', function (hooks) {
  let realm: Realm;
  let adapter: TestRealmAdapter
  setupRenderingTest(hooks);

  hooks.beforeEach(async function() {
    Loader.destroy();
    Loader.addURLMapping(
      new URL(baseRealm.url),
      new URL('http://localhost:4201/base/')
    );
    adapter = new TestRealmAdapter({});
    realm = TestRealm.createWithAdapter(adapter);
    Loader.addRealmFetchOverride(realm);
    await realm.ready;
    this.owner.register('service:local-realm', MockLocalRealm);
  })

  test('renders card schema view', async function (assert) {
    await realm.write('person.gts', `
      import { contains, field, Card } from "https://cardstack.com/base/card-api";
      import StringCard from "https://cardstack.com/base/string";

      export class Person extends Card {
        @field firstName = contains(StringCard);
        @field lastName = contains(StringCard);
      }
    `);
    let { ref, openFile, moduleSyntax } = await getSchemaArgs(this, adapter, { module: `${testRealmURL}person`, name: 'Person'});
    await renderComponent(
      class TestDriver extends GlimmerComponent {
        <template>
          <Schema @ref={{ref}} @file={{openFile}} @moduleSyntax={{moduleSyntax}} />
        </template>
      }
    );

    await waitFor('[data-test-card-id]');

    assert.dom('[data-test-card-id]').hasText(`Card ID: ${testRealmURL}person/Person`);
    assert.dom('[data-test-adopts-from').hasText('Adopts From: https://cardstack.com/base/card-api/Card');
    assert.dom('[data-test-field="firstName"]').hasText('Delete firstName - contains - field card ID: https://cardstack.com/base/string/default');
  });

  test('renders link to field card for contained field', async function(assert) {
    await realm.write('person.gts', `
      import { contains, field, Card } from "https://cardstack.com/base/card-api";
      import StringCard from "https://cardstack.com/base/string";

      export class Person extends Card {
        @field firstName = contains(StringCard);
        @field lastName = contains(StringCard);
      }
    `);
    await realm.write('post.gts', `
      import { contains, field, Card } from "https://cardstack.com/base/card-api";
      import StringCard from "https://cardstack.com/base/string";
      import { Person } from "./person";

      export class Post extends Card {
        @field title = contains(StringCard);
        @field author = contains(Person);
      }
    `);
    let { ref, openFile, moduleSyntax } = await getSchemaArgs(this, adapter, { module: `${testRealmURL}post`, name: 'Post'});
    await renderComponent(
      class TestDriver extends GlimmerComponent {
        <template>
          <Schema @ref={{ref}} @file={{openFile}} @moduleSyntax={{moduleSyntax}} />
        </template>
      }
    );

    await waitFor('[data-test-card-id]');
    assert.dom('[data-test-field="author"] a[href="/?path=person"]').exists('link to person card exists');
    assert.dom('[data-test-field="title"]').exists('the title field exists')
    assert.dom('[data-test-field="title"] a').doesNotExist('the title field has no link');
  });

  test('can delete a field from card', async function(assert){ 
    await realm.write('person.gts', `
      import { contains, field, Card } from "https://cardstack.com/base/card-api";
      import StringCard from "https://cardstack.com/base/string";

      export class Person extends Card {
        @field firstName = contains(StringCard);
        @field lastName = contains(StringCard);
      }
    `);
    let { ref, openFile, moduleSyntax } = await getSchemaArgs(this, adapter, { module: `${testRealmURL}person`, name: 'Person'});
    await renderComponent(
      class TestDriver extends GlimmerComponent {
        <template>
          <Schema @ref={{ref}} @file={{openFile}} @moduleSyntax={{moduleSyntax}} />
        </template>
      }
    );

    await waitFor('[data-test-card-id]');
    await click('[data-test-field="firstName"] button[data-test-delete]');
    let fileRef = await adapter.openFile('person.gts');
    let src = fileRef?.content as string;
    assert.codeEqual(src, `
      import { contains, field, Card } from "https://cardstack.com/base/card-api";
      import StringCard from "https://cardstack.com/base/string";

      export class Person extends Card {
        @field lastName = contains(StringCard);
      }
    `)
  });

  test('does not include a delete button for fields that are inherited', async function (assert) {
    await realm.write('person.gts', `
      import { contains, field, Card } from "https://cardstack.com/base/card-api";
      import StringCard from "https://cardstack.com/base/string";

      export class Person extends Card {
        @field firstName = contains(StringCard);
        @field lastName = contains(StringCard);
      }
    `);
    await realm.write('fancy-person.gts', `
      import { contains, field, Card } from "https://cardstack.com/base/card-api";
      import StringCard from "https://cardstack.com/base/string";
      import { Person } from "./person";

      export class FancyPerson extends Person {
        @field favoriteColor = contains(StringCard);
      }
    `);
    let { ref, openFile, moduleSyntax } = await getSchemaArgs(this, adapter, { module: `${testRealmURL}fancy-person`, name: 'FancyPerson'});
    await renderComponent(
      class TestDriver extends GlimmerComponent {
        <template>
          <Schema @ref={{ref}} @file={{openFile}} @moduleSyntax={{moduleSyntax}} />
        </template>
      }
    );

    await waitFor('[data-test-card-id]');
    assert.dom('[data-test-field="firstName"]').exists('firstName field exists');
    assert.dom('[data-test-field="firstName"] button[data-test-delete]').doesNotExist('delete button does not exist');
    assert.dom('[data-test-field="favoriteColor"] button[data-test-delete]').exists('delete button exists');
  });

  test('it can add a new contains field to a card', async function(assert) {
    await realm.write('person.gts', `
      import { contains, field, Card } from "https://cardstack.com/base/card-api";
      import StringCard from "https://cardstack.com/base/string";

      export class Person extends Card {
        @field firstName = contains(StringCard);
        @field lastName = contains(StringCard);
      }
    `);
    await realm.write('post.gts', `
      import { contains, field, Card } from "https://cardstack.com/base/card-api";
      import StringCard from "https://cardstack.com/base/string";

      export class Post extends Card {
        @field title = contains(StringCard);
      }
    `);
    await realm.write('person-entry.json', JSON.stringify({
      data: {
        type: 'card',
        attributes: {
          title: 'Person',
          description: 'Catalog entry',
          ref: {
            module: `${testRealmURL}person`,
            name: 'Person'
          }
        },
        meta: {
          adoptsFrom: {
            module:`${baseRealm.url}catalog-entry`,
            name: 'CatalogEntry'
          }
        }
      }
    }));
    await realm.write('post-entry.json', JSON.stringify({
      data: {
        type: 'card',
        attributes: {
          title: 'Post',
          description: 'Catalog entry',
          ref: {
            module: `${testRealmURL}post`,
            name: 'Post'
          }
        },
        meta: {
          adoptsFrom: {
            module:`${baseRealm.url}catalog-entry`,
            name: 'CatalogEntry'
          }
        }
      }
    }));
    let { ref, openFile, moduleSyntax } = await getSchemaArgs(this, adapter, { module: `${testRealmURL}post`, name: 'Post'});
    await renderComponent(
      class TestDriver extends GlimmerComponent {
        <template>
          <Schema @ref={{ref}} @file={{openFile}} @moduleSyntax={{moduleSyntax}} />
          <CardCatalogModal />
        </template>
      }
    );

    await waitFor('[data-test-card-id]');
    await fillIn('[data-test-new-field-name]', 'author');
    await click('[data-test-add-field]');
    await waitFor('[data-test-card-catalog-modal] [data-test-ref]');

    assert.dom(`[data-test-card-catalog] [data-test-card-catalog-item="${testRealmURL}person-entry"]`).exists('local realm composite card displayed');
    assert.dom(`[data-test-card-catalog] [data-test-card-catalog-item="${baseRealm.url}fields/boolean-field`).exists('base realm primitive field displayed');
    assert.dom(`[data-test-card-catalog] [data-test-card-catalog-item="${baseRealm.url}fields/card-field`).exists('base realm primitive field displayed');
    assert.dom(`[data-test-card-catalog] [data-test-card-catalog-item="${baseRealm.url}fields/card-ref-field`).exists('base realm primitive field displayed');
    assert.dom(`[data-test-card-catalog] [data-test-card-catalog-item="${baseRealm.url}fields/date-field`).exists('base realm primitive field displayed');
    assert.dom(`[data-test-card-catalog] [data-test-card-catalog-item="${baseRealm.url}fields/datetime-field`).exists('base realm primitive field displayed');
    assert.dom(`[data-test-card-catalog] [data-test-card-catalog-item="${baseRealm.url}fields/integer-field`).exists('base realm primitive field displayed');
    assert.dom(`[data-test-card-catalog] [data-test-card-catalog-item="${baseRealm.url}fields/string-field`).exists('base realm primitive field displayed');

    assert.dom('[data-test-demo-embedded]').exists({ count: 1 }, 'demo card is not displayed for primitive fields');

    // a "contains" field cannot be the same card as it's enclosing card
    assert.dom(`[data-test-card-catalog] [data-test-card-catalog-item="${testRealmURL}post-entry"]`).doesNotExist('own card is not available to choose as a field');

    await click(`[data-test-select="${testRealmURL}person-entry"]`);
    await waitFor('.schema [data-test-field="author"]')
    assert.dom('[data-test-field="author"]').hasText(`Delete author - contains - field card ID: ${testRealmURL}person/Person`);

    let fileRef = await adapter.openFile('post.gts');
    let src = fileRef?.content as string;
    assert.codeEqual(src, `
      import { Person as PersonCard } from "${testRealmURL}person";
      import { contains, field, Card } from "https://cardstack.com/base/card-api";
      import StringCard from "https://cardstack.com/base/string";

      export class Post extends Card {
        @field title = contains(StringCard);
        @field author = contains(PersonCard);
      }
    `);
  });

  test('it can add containsMany field to a card', async function(assert) {
    await realm.write('person.gts', `
      import { contains, field, Card } from "https://cardstack.com/base/card-api";
      import StringCard from "https://cardstack.com/base/string";

      export class Person extends Card {
        @field firstName = contains(StringCard);
        @field lastName = contains(StringCard);
      }
    `);
    let { ref, openFile, moduleSyntax } = await getSchemaArgs(this, adapter, { module: `${testRealmURL}person`, name: 'Person'});
    await renderComponent(
      class TestDriver extends GlimmerComponent {
        <template>
          <Schema @ref={{ref}} @file={{openFile}} @moduleSyntax={{moduleSyntax}} />
          <CardCatalogModal />
        </template>
      }
    );

    await waitFor('[data-test-card-id]');
    await fillIn('[data-test-new-field-name]', 'aliases');
    await click('[data-test-new-field-containsMany]');
    await click('[data-test-add-field]');
    await waitFor('[data-test-card-catalog-modal] [data-test-ref]');

    await click(`[data-test-select="${baseRealm.url}fields/string-field"]`);
    await waitFor('.schema [data-test-field="aliases"]')

    assert.dom('[data-test-field="aliases"]').hasText(`Delete aliases - containsMany - field card ID: ${baseRealm.url}string/default`);

    let fileRef = await adapter.openFile('person.gts');
    let src = fileRef?.content as string;
    assert.codeEqual(src, `
      import { contains, field, Card, containsMany } from "https://cardstack.com/base/card-api";
      import StringCard from "https://cardstack.com/base/string";

      export class Person extends Card {
        @field firstName = contains(StringCard);
        @field lastName = contains(StringCard);
        @field aliases = containsMany(StringCard);
      }
    `);
  });

  test('it does not allow duplicate field to be created', async function (assert){
    await realm.write('person.gts', `
      import { contains, field, Card } from "https://cardstack.com/base/card-api";
      import StringCard from "https://cardstack.com/base/string";

      export class Person extends Card {
        @field firstName = contains(StringCard);
        @field lastName = contains(StringCard);
      }
    `);
    await realm.write('employee.gts', `
      import { contains, field } from "https://cardstack.com/base/card-api";
      import StringCard from "https://cardstack.com/base/string";
      import { Person } from "./person";

      export class Employee extends Person {
        @field department = contains(StringCard);
      }
    `);

    let { ref, openFile, moduleSyntax } = await getSchemaArgs(this, adapter, { module: `${testRealmURL}employee`, name: 'Employee'});
    await renderComponent(
      class TestDriver extends GlimmerComponent {
        <template>
          <Schema @ref={{ref}} @file={{openFile}} @moduleSyntax={{moduleSyntax}} />
          <CardCatalogModal />
        </template>
      }
    );

    await waitFor('[data-test-card-id]');
    assert.dom('data-test-error-msg').doesNotExist('error message does not exist');

    await fillIn('[data-test-new-field-name]', 'department');
    assert.dom('[data-test-error-msg').hasText('The field name "department" already exists, please choose a different name.');
    await fillIn('[data-test-new-field-name]', 'firstName');
    assert.dom('[data-test-error-msg').hasText('The field name "firstName" already exists, please choose a different name.');
    await fillIn('[data-test-new-field-name]', 'newFieldName');
    assert.dom('data-test-error-msg').doesNotExist('error message does not exist');
  });
});


async function getSchemaArgs(context: TestContext, adapter: TestRealmAdapter, ref: ExportedCardRef): Promise<{
  openFile: FileResource;
  moduleSyntax: ModuleSyntax;
  ref: ExportedCardRef;
}> {
  let fileURL = ref.module.endsWith('.gts') ? ref.module : `${ref.module}.gts`;
  let paths = new RealmPaths(testRealmURL);
  let content = (await adapter.openFile(paths.local(new URL(fileURL))))?.content as string | undefined;
  let openFile = file(context, () => ({
    url: fileURL,
    lastModified: undefined,
    content
  }));
  await openFile.loading;
  if (openFile.state !== "ready") {
    throw new Error(`could not open file ${openFile.url}`);
  }
  let moduleSyntax = new ModuleSyntax(openFile.content, new URL(openFile.url));
  return { moduleSyntax, ref, openFile };
}