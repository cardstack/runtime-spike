import { transformSync } from '@babel/core';
// import * as Babel from '@babel/core';
import {
  schemaAnalysisPlugin,
  Options,
  PossibleCardClass,
  CardReference,
  PossibleField,
} from './schema-analysis-plugin';

import { parseTemplates } from 'ember-template-imports/lib/parse-templates';

import { fieldDecorator, fieldType, FieldType, isFieldType } from './card-api';
//@ts-ignore unsure where these types live
import decoratorsPlugin from '@babel/plugin-syntax-decorators';
//@ts-ignore unsure where these types live
import classPropertiesPlugin from '@babel/plugin-syntax-class-properties';
//@ts-ignore unsure where these types live
import typescriptPlugin from '@babel/plugin-transform-typescript';

// represents the cards within an entire javascript module
export class CardDefinitions {
  // private ast: Babel.types.File;
  private possibleCards: PossibleCardClass[];

  static async create(
    src: string,
    inspector: CardInspector
  ): Promise<CardDefinitions> {
    let definitions = new CardDefinitions(src, inspector);
    await definitions.semanticPhase();
    return definitions;
  }

  private constructor(private src: string, private inspector: CardInspector) {
    // construct handles the synchronous syntactic phase
    let moduleAnalysis: Options = { possibleCards: [] };
    let preprocessedSrc = this.preprocessTemplateTags();

    this.ast = transformSync(preprocessedSrc, {
      code: false,
      ast: true,
      plugins: [
        typescriptPlugin,
        [decoratorsPlugin, { legacy: true }],
        classPropertiesPlugin,
        [schemaAnalysisPlugin, moduleAnalysis],
      ],
    })!.ast!;
    this.possibleCards = moduleAnalysis.possibleCards;
  }

  private preprocessTemplateTags(): string {
    let output = [];
    let offset = 0;
    let matches = parseTemplates(this.src, 'no-filename', 'template');
    for (let match of matches) {
      output.push(this.src.slice(offset, match.start.index));
      output.push('[templte(`'); // use back tick so we can be tolerant of newlines
      output.push(
        this.src
          .slice(match.start.index! + match.start[0].length, match.end.index)
          .replace(/`/g, '\\`')
      );
      output.push('`)]        ');
      offset = match.end.index! + match.end[0].length;
    }
    output.push(this.src.slice(offset));
    return output.join('');
  }

  // the semantic phase is async
  private async semanticPhase() {
    for (let card of this.possibleCards) {
      if (await this.isCardReference(card.super)) {
        let fields: Map<string, FieldDefinition> = new Map();
        for (let [fieldName, field] of card.possibleFields) {
          let fieldType = await this.getFieldType(field);
          if (!fieldType) {
            continue;
          }
          if (!(await this.isCardReference(field.card))) {
            continue;
          }
          fields.set(fieldName, {
            type: fieldType,
            card: field.card,
          });
        }
        this.cards.push(new CardDefinition(card, fields));
      }
    }
  }

  private async isCardReference(
    possibleCardRef: CardReference
  ): Promise<boolean> {
    switch (possibleCardRef.type) {
      case 'external': {
        let mod = await this.inspector.resolveModule(possibleCardRef.module);
        let superClass = mod[possibleCardRef.name];
        return typeof superClass === 'function' && 'baseCard' in superClass;
      }
      case 'internal':
        return await this.isCardReference(
          this.possibleCards[possibleCardRef.classIndex].super
        );
      default:
        throw assertNever(possibleCardRef);
    }
  }

  private async getFieldType(
    possibleField: PossibleField
  ): Promise<FieldType | undefined> {
    let decoratorMod = await this.inspector.resolveModule(
      possibleField.decorator.module
    );
    if (!(fieldDecorator in decoratorMod[possibleField.decorator.name])) {
      return undefined;
    }
    let fieldTypeMod = await this.inspector.resolveModule(
      possibleField.type.module
    );

    if (!(await this.isCardReference(possibleField.card))) {
      return undefined;
    }
    let type = fieldTypeMod[possibleField.type.name][fieldType];
    if (!isFieldType(type)) {
      return undefined;
    }

    return type;
  }

  cards: CardDefinition[] = [];
}

export class CardDefinition {
  constructor(
    private cardClass: PossibleCardClass,
    private fieldDefinitions: Map<string, FieldDefinition>
  ) {}

  getField(name: string) {
    return this.fieldDefinitions.get(name);
  }
  get localName() {
    return this.cardClass.localName;
  }
  get exportedAs() {
    return this.cardClass.exportedAs;
  }
  get fields() {
    return [...this.fieldDefinitions];
  }
}

export interface FieldDefinition {
  card: CardReference;
  type: FieldType;
}

export class CardInspector {
  readonly resolveModule: (specifier: string) => Promise<Record<string, any>>;

  constructor(params: {
    resolveModule: (specifier: string) => Promise<Record<string, any>>;
  }) {
    this.resolveModule = params.resolveModule;
  }

  async inspectCards(src: string): Promise<CardDefinitions> {
    return await CardDefinitions.create(src, this);
  }
}

function assertNever(value: never) {
  throw new Error(`should never happen ${value}`);
}