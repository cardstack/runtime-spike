import { module, test } from "qunit";
import { ModuleSyntax } from "@cardstack/runtime-common/module-syntax";
import "@cardstack/runtime-common/helpers/code-equality-assertion";

const testURL = new URL("http://test-realm/module");

module("module-syntax", function () {
  test("can get the code for a card", async function (assert) {
    let src = `
      import { contains, field, Component, Card } from "https://cardstack.com/base/card-api";
      import StringCard from "https://cardstack.com/base/string";

      export class Person extends Card {
        @field firstName = contains(StringCard);
        static embedded = class Embedded extends Component<typeof this> {
          <template><h1><@fields.firstName/></h1></template>
        }
      }
    `;

    let mod = new ModuleSyntax(src, testURL);
    assert.codeEqual(mod.code(), src);
  });

  test("can add a field to a card", async function (assert) {
    let src = `
      import { contains, field, Component, Card } from "https://cardstack.com/base/card-api";
      import StringCard from "https://cardstack.com/base/string";

      export class Person extends Card {
        @field firstName = contains(StringCard);
        static embedded = class Embedded extends Component<typeof this> {
          <template><h1><@fields.firstName/></h1></template>
        }
      }
    `;

    let mod = new ModuleSyntax(src, testURL);
    mod.addField(
      { type: "exportedName", name: "Person" },
      "age",
      {
        module: "https://cardstack.com/base/integer",
        name: "default",
      },
      "contains"
    );

    assert.codeEqual(
      mod.code(),
      `
        import IntegerCard from "https://cardstack.com/base/integer";
        import { contains, field, Component, Card } from "https://cardstack.com/base/card-api";
        import StringCard from "https://cardstack.com/base/string";

        export class Person extends Card {
          @field firstName = contains(StringCard);
          @field age = contains(IntegerCard);
          static embedded = class Embedded extends Component<typeof this> {
            <template><h1><@fields.firstName/></h1></template>
          }
        }
      `
    );

    let card = mod.possibleCards.find((c) => c.exportedAs === "Person");
    let field = card!.possibleFields.get("age");
    assert.ok(field, "new field was added to syntax");
    assert.deepEqual(
      field?.card,
      {
        type: "external",
        module: "https://cardstack.com/base/integer",
        name: "default",
      },
      "the field card is correct"
    );
    assert.deepEqual(
      field?.type,
      {
        type: "external",
        module: "https://cardstack.com/base/card-api",
        name: "contains",
      },
      "the field type is correct"
    );
    assert.deepEqual(
      field?.decorator,
      {
        type: "external",
        module: "https://cardstack.com/base/card-api",
        name: "field",
      },
      "the field decorator is correct"
    );

    // add another field which will assert that the field path is correct since
    // the new field must go after this field
    mod.addField(
      { type: "exportedName", name: "Person" },
      "lastName",
      {
        module: "https://cardstack.com/base/string",
        name: "default",
      },
      "contains"
    );
    assert.codeEqual(
      mod.code(),
      `
        import IntegerCard from "https://cardstack.com/base/integer";
        import { contains, field, Component, Card } from "https://cardstack.com/base/card-api";
        import StringCard from "https://cardstack.com/base/string";

        export class Person extends Card {
          @field firstName = contains(StringCard);
          @field age = contains(IntegerCard);
          @field lastName = contains(StringCard);
          static embedded = class Embedded extends Component<typeof this> {
            <template><h1><@fields.firstName/></h1></template>
          }
        }
      `
    );
  });

  test("can add a field to a card that doesn't have any fields", async function (assert) {
    let src = `
        import { Card } from "https://cardstack.com/base/card-api";

        export class Person extends Card { }
      `;

    let mod = new ModuleSyntax(src, testURL);
    mod.addField(
      { type: "exportedName", name: "Person" },
      "firstName",
      {
        module: "https://cardstack.com/base/string",
        name: "default",
      },
      "contains"
    );

    assert.codeEqual(
      mod.code(),
      `
          import StringCard from "https://cardstack.com/base/string";
          import { Card, field, contains } from "https://cardstack.com/base/card-api";

          export class Person extends Card {
            @field firstName = contains(StringCard);
          }
        `
    );
  });

  test("can add a field to a card that is not exported", async function (assert) {
    let src = `
      import { contains, field, Component, Card } from "https://cardstack.com/base/card-api";
      import StringCard from "https://cardstack.com/base/string";

      class Person extends Card {
        @field firstName = contains(StringCard);
        static embedded = class Embedded extends Component<typeof this> {
          <template><h1><@fields.firstName/></h1></template>
        }
      }

      export class FancyPerson extends Person {
        @field favoriteColor = contains(StringCard);
      }
    `;

    let mod = new ModuleSyntax(src, testURL);
    mod.addField(
      { type: "localName", name: "Person" },
      "age",
      {
        module: "https://cardstack.com/base/integer",
        name: "default",
      },
      "contains"
    );

    assert.codeEqual(
      mod.code(),
      `
        import IntegerCard from "https://cardstack.com/base/integer";
        import { contains, field, Component, Card } from "https://cardstack.com/base/card-api";
        import StringCard from "https://cardstack.com/base/string";

        class Person extends Card {
          @field firstName = contains(StringCard);
          @field age = contains(IntegerCard);
          static embedded = class Embedded extends Component<typeof this> {
            <template><h1><@fields.firstName/></h1></template>
          }
        }

        export class FancyPerson extends Person {
          @field favoriteColor = contains(StringCard);
        }
      `
    );
  });

  test("can add a containsMany field", async function (assert) {
    let src = `
      import { contains, field, Component, Card } from "https://cardstack.com/base/card-api";
      import StringCard from "https://cardstack.com/base/string";

      export class Person extends Card {
        @field firstName = contains(StringCard);
        static embedded = class Embedded extends Component<typeof this> {
          <template><h1><@fields.firstName/></h1></template>
        }
      }
    `;

    let mod = new ModuleSyntax(src, testURL);
    mod.addField(
      { type: "exportedName", name: "Person" },
      "aliases",
      {
        module: "https://cardstack.com/base/string",
        name: "default",
      },
      "containsMany"
    );

    assert.codeEqual(
      mod.code(),
      `
        import { contains, field, Component, Card, containsMany } from "https://cardstack.com/base/card-api";
        import StringCard from "https://cardstack.com/base/string";

        export class Person extends Card {
          @field firstName = contains(StringCard);
          @field aliases = containsMany(StringCard);
          static embedded = class Embedded extends Component<typeof this> {
            <template><h1><@fields.firstName/></h1></template>
          }
        }
      `
    );
    let card = mod.possibleCards.find((c) => c.exportedAs === "Person");
    let field = card!.possibleFields.get("aliases");
    assert.ok(field, "new field was added to syntax");
    assert.deepEqual(
      field?.type,
      {
        type: "external",
        module: "https://cardstack.com/base/card-api",
        name: "containsMany",
      },
      "the field type is correct"
    );
  });

  test("can handle field card declaration collisions when adding field", async function (assert) {
    let src = `
      import { contains, field, Card } from "https://cardstack.com/base/card-api";
      import StringCard from "https://cardstack.com/base/string";

      const IntegerCard = "don't collide with me";

      export class Person extends Card {
        @field firstName = contains(StringCard);
      }
    `;

    let mod = new ModuleSyntax(src, testURL);
    mod.addField(
      { type: "exportedName", name: "Person" },
      "age",
      {
        module: "https://cardstack.com/base/integer",
        name: "default",
      },
      "contains"
    );

    assert.codeEqual(
      mod.code(),
      `
        import IntegerCard0 from "https://cardstack.com/base/integer";
        import { contains, field, Card } from "https://cardstack.com/base/card-api";
        import StringCard from "https://cardstack.com/base/string";

        const IntegerCard = "don't collide with me";

        export class Person extends Card {
          @field firstName = contains(StringCard);
          @field age = contains(IntegerCard0);
        }
      `
    );
  });

  // At this level, we can only see this specific module. we'll need the
  // upstream caller to perform a field existence check on the card
  // definition to ensure this field does not already exist in the adoption chain
  test("throws when adding a field with a name the card already has", async function (assert) {
    let src = `
      import { contains, field, Card } from "https://cardstack.com/base/card-api";
      import StringCard from "https://cardstack.com/base/string";

      export class Person extends Card {
        @field firstName = contains(StringCard);
      }
    `;
    let mod = new ModuleSyntax(src, testURL);
    try {
      mod.addField(
        { type: "exportedName", name: "Person" },
        "firstName",
        {
          module: "https://cardstack.com/base/string",
          name: "default",
        },
        "contains"
      );
      throw new Error("expected error was not thrown");
    } catch (err: any) {
      assert.ok(
        err.message.match(/field "firstName" already exists/),
        "expected error was thrown"
      );
    }
  });

  test("can remove a field from a card", async function (assert) {
    let src = `
      import { contains, field, Card } from "https://cardstack.com/base/card-api";
      import StringCard from "https://cardstack.com/base/string";

      export class Person extends Card {
        @field firstName = contains(StringCard);
        @field lastName = contains(StringCard);
      }
    `;
    let mod = new ModuleSyntax(src, testURL);
    mod.removeField({ type: "exportedName", name: "Person" }, "firstName");

    assert.codeEqual(
      mod.code(),
      `
        import { contains, field, Card } from "https://cardstack.com/base/card-api";
        import StringCard from "https://cardstack.com/base/string";

        export class Person extends Card {
          @field lastName = contains(StringCard);
        }
      `
    );

    let card = mod.possibleCards.find((c) => c.exportedAs === "Person");
    let field = card!.possibleFields.get("firstName");
    assert.strictEqual(field, undefined, "field does not exist in syntax");
  });

  test("can remove the last field from a card", async function (assert) {
    let src = `
      import { contains, field, Card } from "https://cardstack.com/base/card-api";
      import StringCard from "https://cardstack.com/base/string";

      export class Person extends Card {
        @field firstName = contains(StringCard);
      }
    `;

    let mod = new ModuleSyntax(src, testURL);
    mod.removeField({ type: "exportedName", name: "Person" }, "firstName");

    assert.codeEqual(
      mod.code(),
      `
        import { Card } from "https://cardstack.com/base/card-api";
        export class Person extends Card { }
      `
    );
  });

  test("can remove the field from a card that is not exported", async function (assert) {
    let src = `
      import { contains, field, Component, Card } from "https://cardstack.com/base/card-api";
      import StringCard from "https://cardstack.com/base/string";

      class Person extends Card {
        @field firstName = contains(StringCard);
        @field lastName = contains(StringCard);
      }

      export class FancyPerson extends Person {
        @field favoriteColor = contains(StringCard);
      }
    `;
    let mod = new ModuleSyntax(src, testURL);
    mod.removeField({ type: "localName", name: "Person" }, "firstName");

    assert.codeEqual(
      mod.code(),
      `
        import { contains, field, Component, Card } from "https://cardstack.com/base/card-api";
        import StringCard from "https://cardstack.com/base/string";

        class Person extends Card {
          @field lastName = contains(StringCard);
        }

        export class FancyPerson extends Person {
          @field favoriteColor = contains(StringCard);
        }
      `
    );
  });

  test("throws when field to remove does not actually exist", async function (assert) {
    let src = `
      import { contains, field, Component, Card } from "https://cardstack.com/base/card-api";
      import StringCard from "https://cardstack.com/base/string";

      export class Person extends Card {
        @field firstName = contains(StringCard);
      }
    `;

    let mod = new ModuleSyntax(src, testURL);
    try {
      mod.removeField({ type: "exportedName", name: "Person" }, "foo");
      throw new Error("expected error was not thrown");
    } catch (err: any) {
      assert.ok(
        err.message.match(/field "foo" does not exist/),
        "expected error was thrown"
      );
    }
  });
});
