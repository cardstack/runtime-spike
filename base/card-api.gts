import GlimmerComponent from '@glimmer/component';
import type { ComponentLike } from '@glint/template';
import { NotReady, isNotReadyError} from './not-ready';
import { flatMap, startCase, merge } from 'lodash';
import { TrackedWeakMap } from 'tracked-built-ins';
import { WatchedArray } from './watched-array';
import { flatten } from "flat";
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { pick } from './pick';
import ShadowDOM from 'https://cardstack.com/base/shadow-dom';
import { initStyleSheet, attachStyles } from 'https://cardstack.com/base/attach-styles';
import { restartableTask } from 'ember-concurrency';
import { taskFor } from 'ember-concurrency-ts';
import {
  Deferred,
  isCardResource,
  Loader,
  isSingleCardDocument,
  isRelationship,
  isNotLoadedError,
  CardError,
  NotLoaded,
  chooseCard,
  baseCardRef,
  maxLinkDepth,
  type Meta,
  type CardFields,
  type Relationship,
  type LooseCardResource,
  type LooseSingleCardDocument,
  type CardDocument,
  type CardResource,
  type ExportedCardRef
} from '@cardstack/runtime-common';
export const primitive = Symbol('cardstack-primitive');
export const serialize = Symbol('cardstack-serialize');
export const deserialize = Symbol('cardstack-deserialize');
export const useIndexBasedKey = Symbol('cardstack-use-index-based-key');
export const fieldDecorator = Symbol('cardstack-field-decorator');
export const fieldType = Symbol('cardstack-field-type');
export const queryableValue = Symbol('cardstack-queryable-value');
// intentionally not exporting this so that the outside world
// cannot mark a card as being saved
const isSavedInstance = Symbol('cardstack-is-saved-instance');
const isField = Symbol('cardstack-field');

export type CardInstanceType<T extends CardConstructor> = T extends { [primitive]: infer P } ? P : InstanceType<T>;
export type PartialCardInstanceType<T extends CardConstructor> = T extends { [primitive]: infer P } ? P | null : Partial<InstanceType<T>>;

type FieldsTypeFor<T extends Card> = {
  [Field in keyof T]: (new() => GlimmerComponent<{ Args: {}, Blocks: {} }>) & (T[Field] extends Card ? FieldsTypeFor<T[Field]> : unknown);
}

type Setter = { setters: { [fieldName: string]: Setter }} & ((value: any) => void);


export type Format = 'isolated' | 'embedded' | 'edit';
export type FieldType = 'contains' | 'containsMany' | 'linksTo'; 

interface Options {
  computeVia?: string | (() => unknown);
}

interface NotLoadedValue {
  type: 'not-loaded';
  reference: string;
}

function isNotLoadedValue(val: any): val is NotLoadedValue {
  if (!val || typeof val !== 'object') {
    return false;
  }
  if (!("type" in val) || !("reference" in val)) {
    return false;
  }
  let { type, reference } = val;
  if (typeof type !== "string" || typeof reference !== "string") {
    return false;
  }
  return type === "not-loaded";
}

const deserializedData = new WeakMap<object, Map<string, any>>();
const recomputePromises = new WeakMap<Card, Promise<any>>();
const componentCache = new WeakMap<Box<unknown>, ComponentLike<{ Args: {}; Blocks: {}; }>>();
const identityContexts = new WeakMap<Card, IdentityContext>();

// our place for notifying Glimmer when a card is ready to re-render (which will
// involve rerunning async computed fields)
const cardTracking = new TrackedWeakMap<object, any>();

const isBaseCard = Symbol('isBaseCard');

class Logger {
  private promises:Promise<any>[] = [];

  log(promise: Promise<any>) {
    this.promises.push(promise);
    (async () => await promise)(); // make an effort to resolve the promise at the time it is logged
  }

  async flush() {
    let results = await Promise.allSettled(this.promises);
    for (let result of results) {
      if (result.status === 'rejected') {
        console.error(`Promise rejected`, result.reason);
        if (result.reason instanceof Error) {
          console.error(result.reason.stack);
        }
      }
    }
  }
}

let logger = new Logger();
export async function flushLogs() {
  await logger.flush();
}

export class IdentityContext {
  readonly identities = new Map<string, Card>();
}

type JSONAPIResource = 
{ 
  attributes: Record<string, any>;
  relationships?: Record<string, Relationship>;
  meta?: Record<string, any>;
} | 
{ 
  attributes?: Record<string, any>;
  relationships: Record<string, Relationship>;
  meta?: Record<string, any>;
}

interface JSONAPISingleResourceDocument {
  data: Partial<JSONAPIResource> & { id?: string, type: string };
  included?: (Partial<JSONAPIResource> & { id: string, type: string })[];
}

interface Field<CardT extends CardConstructor> {
  card: CardT;
  name: string;
  fieldType: FieldType;
  computeVia: undefined | string | (() => unknown);
  serialize(value: any, doc: JSONAPISingleResourceDocument, visited: Set<string>): JSONAPIResource;
  deserialize(
    value: any,
    doc: LooseSingleCardDocument | CardDocument,
    relationships: JSONAPIResource["relationships"] | undefined,
    fieldMeta: CardFields[string] | undefined,
    identityContext: IdentityContext | undefined,
    instancePromise: Promise<Card>
  ): Promise<any>;
  emptyValue(instance: Card): any;
  validate(instance: Card, value: any): void;
  component(model: Box<Card>, format: Format): ComponentLike<{ Args: {}, Blocks: {} }>;
  getter(instance: Card): CardInstanceType<CardT>;
}

function callSerializeHook(card: typeof Card, value: any, doc: JSONAPISingleResourceDocument, visited: Set<string> = new Set()) {
  if (value != null) {
    return card[serialize](value, doc, visited);
  } else {
    return null;
  }
}

function cardTypeFor(field: Field<typeof Card>, boxedElement: Box<Card>): typeof Card {
  if (primitive in field.card) {
      return field.card;
  }
  return Reflect.getPrototypeOf(boxedElement.value)!.constructor as typeof Card;
}

function resourceFrom(doc: CardDocument | undefined, resourceId: string | undefined): LooseCardResource | undefined {
  if (doc == null) {
    return undefined;
  }
  let data: CardResource[];
  if (isSingleCardDocument(doc)) {
    if (resourceId == null) {
      return doc.data;
    }
    data = [doc.data];
  } else {
    data = doc.data;
  }
  let res = [...data, ...(doc.included ?? [])].find(resource => resource.id === resourceId);
  return res;
}

function getter<CardT extends CardConstructor>(instance: Card, field: Field<CardT>): CardInstanceType<CardT> {
  let deserialized = getDataBucket(instance);
  // this establishes that our field should rerender when cardTracking for this card changes
  cardTracking.get(instance);

  if (field.computeVia) {
    let value = deserialized.get(field.name);
    if (value === undefined && typeof field.computeVia === 'function' && field.computeVia.constructor.name !== 'AsyncFunction') {
      value = field.computeVia.bind(instance)();
      deserialized.set(field.name, value);
    } else if (value === undefined && (typeof field.computeVia === 'string' || typeof field.computeVia === 'function')) {
      throw new NotReady(instance, field.name, field.computeVia, instance.constructor.name);
    }
    return value;
  } else {
    if (deserialized.has(field.name)) {
      return deserialized.get(field.name);
    }
    let value = field.emptyValue(instance);
    deserialized.set(field.name, value);
    return value;
  }
}

class ContainsMany<FieldT extends CardConstructor> implements Field<FieldT> {
  readonly fieldType = 'containsMany';
  constructor(
    private cardThunk: () => FieldT,
    readonly computeVia: undefined | string | (() => unknown),
    readonly name: string
  ) {}

  get card(): FieldT {
    return this.cardThunk();
  }

  getter(instance: Card): CardInstanceType<FieldT> {
    return getter(instance, this);
  }

  serialize(values: CardInstanceType<FieldT>[], doc: JSONAPISingleResourceDocument): JSONAPIResource {
    if (primitive in this.card) {
      return { attributes: { [this.name]:  values.map(value => callSerializeHook(this.card, value, doc)) } };
    } else {
      let relationships: Record<string, Relationship> = {};
      let serialized = values.map((value, index) => {
        let resource: JSONAPISingleResourceDocument['data'] = callSerializeHook(this.card, value, doc);
        if (resource.relationships) {
          for (let [fieldName, relationship] of Object.entries(resource.relationships as Record<string, Relationship>)) {
            relationships[`${this.name}.${index}.${fieldName}`] = relationship; // warning side-effect
          }
        }
        if (this.card === Reflect.getPrototypeOf(value)!.constructor) {
          // when our implementation matches the default we don't need to include
          // meta.adoptsFrom
          delete resource.meta?.adoptsFrom;  
        }
        if (resource.meta && Object.keys(resource.meta).length === 0) {
          delete resource.meta;
        }
        return resource;
      });

      let result: JSONAPIResource = { 
        attributes: { 
          [this.name]: serialized.map(resource => resource.attributes )
        }
      };
      if (Object.keys(relationships).length > 0) {
        result.relationships = relationships;
      }

      if (serialized.some(resource => resource.meta)) {
        result.meta = {
          fields: {
            [this.name]: serialized.map(resource => resource.meta ?? {})
          }
        }
      }        

      return result;
    }
  }

  async deserialize(
    value: any[],
    doc: CardDocument,
    relationships: JSONAPIResource["relationships"] | undefined,
    fieldMeta: CardFields[string] | undefined,
    _identityContext: undefined,
    instancePromise: Promise<Card>
  ): Promise<CardInstanceType<FieldT>[]> {
    if (!Array.isArray(value)) {
      throw new Error(`Expected array for field value ${this.name}`);
    }
    if (fieldMeta && !Array.isArray(fieldMeta)) {
      throw new Error(`fieldMeta for contains-many field '${this.name}' is not an array: ${JSON.stringify(fieldMeta, null, 2)}`);
    }
    let metas: Partial<Meta>[] = fieldMeta ?? [];
    return new WatchedArray(
      () => instancePromise.then(instance => logger.log(recompute(instance))),
      await Promise.all(value.map(async (entry, index) => {
        if (primitive in this.card) {
          return this.card[deserialize](entry, doc);
        } else {
          let meta = metas[index];
          let resource: LooseCardResource = {
            attributes: entry,
            meta: makeMetaForField(meta, this.name, this.card)
          }
          if (relationships) {
            resource.relationships = Object.fromEntries(
              Object.entries(relationships)
                .filter(([fieldName]) => fieldName.startsWith(`${this.name}.`))
                .map(([fieldName, relationship]) => {
                  let relName = `${this.name}.${index}`;
                  return [fieldName.startsWith(`${relName}.`) ? fieldName.substring(relName.length + 1) : fieldName, relationship]
                })
              );
          }
          return (await cardClassFromResource(resource, this.card))[deserialize](resource, doc);
        }
      }))
    );
  }

  emptyValue(instance: Card) {
    return new WatchedArray(() => logger.log(recompute(instance)));
  };

  validate(instance: Card, value: any) {
    if (value && !Array.isArray(value)) {
      throw new Error(`Expected array for field value ${this.name}`);
    }
    return new WatchedArray(() => logger.log(recompute(instance)), value);
  }

  component(model: Box<Card>, format: Format) {
    let fieldName = this.name as keyof Card;
    let field = this;
    let arrayField = model.field(fieldName, useIndexBasedKey in this.card) as unknown as Box<Card[]>;
    if (format === 'edit') {
      return class ContainsManyEditorTemplate extends GlimmerComponent {
        <template>
          <ContainsManyEditor
            @model={{model}}
            @arrayField={{arrayField}}
            @field={{field}}
            @format={{format}}
          />
        </template>
      };
    }
    return class ContainsMany extends GlimmerComponent {
      <template>
        {{#each arrayField.children as |boxedElement|}}
          {{#let (getBoxComponent (cardTypeFor field boxedElement) format boxedElement) as |Item|}}
            <Item/>
          {{/let}}
        {{/each}}
      </template>
    };
  }
}

class Contains<CardT extends CardConstructor> implements Field<CardT> {
  readonly fieldType = 'contains';
  constructor(private cardThunk: () => CardT, readonly computeVia: undefined | string | (() => unknown), readonly name: string) {
  }

  get card(): CardT {
    return this.cardThunk();
  }

  getter(instance: Card): CardInstanceType<CardT> {
    return getter(instance, this);
  }

  serialize(value: InstanceType<CardT>, doc: JSONAPISingleResourceDocument): JSONAPIResource {
    let serialized: JSONAPISingleResourceDocument['data'] & { meta: Record<string, any> } = callSerializeHook(this.card, value, doc);
    if (primitive in this.card) {
      return { attributes: { [this.name]: serialized } }
    } else {
      let resource: JSONAPIResource = { 
        attributes: { 
          [this.name]: serialized?.attributes
        }
      };
      if (serialized == null) {
        return resource;
      }
      if (serialized.relationships) {
        resource.relationships = {};
        for (let [fieldName, relationship] of Object.entries(serialized.relationships as Record<string, Relationship>)) {
          resource.relationships[`${this.name}.${fieldName}`] = relationship;
        }
      }

      if (this.card === Reflect.getPrototypeOf(value)!.constructor) {
        // when our implementation matches the default we don't need to include
        // meta.adoptsFrom
        delete serialized.meta.adoptsFrom;  
      }

      if (Object.keys(serialized.meta).length > 0) {
        resource.meta = {
          fields:{ [this.name]: serialized.meta }
        }
      }
      return resource;
    }
  }

  async deserialize(
    value: any,
    doc: CardDocument,
    relationships: JSONAPIResource["relationships"] | undefined,
    fieldMeta: CardFields[string] | undefined
  ): Promise<CardInstanceType<CardT>> {
    if (primitive in this.card) {
      return this.card[deserialize](value, doc);
    }
    if (fieldMeta && Array.isArray(fieldMeta)) {
      throw new Error(`fieldMeta for contains field '${this.name}' is an array: ${JSON.stringify(fieldMeta, null, 2)}`);
    }
    let meta: Partial<Meta> | undefined = fieldMeta;
    let resource: LooseCardResource = { 
      attributes: value,
      meta: makeMetaForField(meta, this.name, this.card)
    };
    if (relationships) {
      resource.relationships = Object.fromEntries(
        Object.entries(relationships)
          .filter(([fieldName]) => fieldName.startsWith(`${this.name}.`))
          .map(([fieldName, relationship]) => 
            [fieldName.startsWith(`${this.name}.`) ? fieldName.substring(this.name.length + 1) : fieldName, relationship]
          )
        );
    }
    return (await cardClassFromResource(resource, this.card))[deserialize](resource, doc);
  }

  emptyValue(_instance: Card) {
    if (primitive in this.card) {
      return undefined;
    } else {
      return new this.card;
    }
  }

  validate(_instance: Card, value: any) {
    if (primitive in this.card) {
      // todo: primitives could implement a validation symbol
    } else {
      if (value != null && !(value instanceof this.card)) {
        throw new Error(`tried set ${value} as field ${this.name} but it is not an instance of ${this.card.name}`);
      }
    }
    return value;
  }

  component(model: Box<Card>, format: Format): ComponentLike<{ Args: {}, Blocks: {} }> {
    return fieldComponent(this, model, format);
  }
}

class LinksTo<CardT extends CardConstructor> implements Field<CardT> {
  readonly fieldType = 'linksTo';
  constructor(private cardThunk: () => CardT, readonly computeVia: undefined | string | (() => unknown), readonly name: string) {
  }

  get card(): CardT {
    return this.cardThunk();
  }

  getter(instance: Card): CardInstanceType<CardT> {
    let deserialized = getDataBucket(instance);
    // this establishes that our field should rerender when cardTracking for this card changes
    cardTracking.get(instance);
    let maybeNotLoaded = deserialized.get(this.name);
    if (isNotLoadedValue(maybeNotLoaded)) {
      throw new NotLoaded(maybeNotLoaded.reference, this.name, instance.constructor.name);
    }
    return getter(instance, this);
  }

  serialize(value: InstanceType<CardT>, doc: JSONAPISingleResourceDocument, visited: Set<string>) {
    if (isNotLoadedValue(value)) {
      return { 
        relationships: { 
          [this.name]: {
            links: { self: value.reference },
          }
        }
      };
    }
    if (value == null) {
      return { 
        relationships: { 
          [this.name]: {
            links: { self: null },
          }
        }
      };
    }
    if (visited.has(value.id)) {
      return {
        relationships: {
          [this.name]: {
            links: { self: value.id },
            data: { type: 'card', id: value.id }
          }
        }
      };
    }
    visited.add(value.id);

    let serialized = callSerializeHook(this.card, value, doc, visited) as (JSONAPIResource & { id: string; type: string }) | null;
    if (serialized) {
      if (!value[isSavedInstance]) {
        throw new Error(`the linksTo field '${this.name}' cannot be serialized with an unsaved card`);
      }
      let resource: JSONAPIResource = { 
        relationships: { 
          [this.name]: {
            links: { self: value.id },
            // we also write out the data form of the relationship
            // which correlates to the included resource
            data: { type: 'card', id: value.id }
          }
        }
      };
      if (!(doc.included ??[]).find(r => r.id === value.id) && doc.data.id !== value.id) {
        doc.included = doc.included ?? [];
        doc.included.push(serialized);
      }
      return resource;
    }
    return { 
      relationships: { 
        [this.name]: {
          links: { self: null },
        }
      }
    };
  }

  async deserialize(
    value: any,
    doc: CardDocument,
    _relationships: undefined,
    _fieldMeta: undefined,
    identityContext: IdentityContext
  ): Promise<CardInstanceType<CardT> | null | NotLoadedValue> {
    if (!isRelationship(value)) {
      throw new Error(`linkTo field '${this.name}' cannot deserialize non-relationship value ${JSON.stringify(value)}`);
    }
    if (value?.links?.self == null) {
      return null;
    }
    let cachedInstance = identityContext.identities.get(value.links.self);
    if (cachedInstance) {
      return cachedInstance as CardInstanceType<CardT>;
    }
    let resource = resourceFrom(doc, value.links.self);
    if (!resource) {
      return {
        type: 'not-loaded',
        reference: value.links.self
      };
    }
    return (await cardClassFromResource(resource, this.card))[deserialize](resource, doc, identityContext);
  }

  emptyValue(_instance: Card) {
    return null;
  }

  validate(_instance: Card, value: any) {
    // we can't actually place this in the constructor since that would break cards whose field type is themselves
    // so the next opportunity we have to test this scenario is during field assignment
    if (primitive in this.card) {
      throw new Error(`the linksTo field '${this.name}' contains a primitive card '${this.card.name}'`);
    }
    if (value) {
      if (isNotLoadedValue(value)) {
        return value;
      }
      if (!(value instanceof this.card)) {
        throw new Error(`tried set ${value} as field '${this.name}' but it is not an instance of ${this.card.name}`);
      }
    }
    return value;
  }

  component(model: Box<Card>, format: Format): ComponentLike<{ Args: {}, Blocks: {} }> {
    if (format === 'edit') {
      let field = this;
      let innerModel = model.field(this.name as keyof Card) as unknown as Box<Card>;
      return class LinksToEditTemplate extends GlimmerComponent {
        <template>
          <LinksToEditor @model={{innerModel}} @field={{field}} />
        </template>
      };
    }
    return fieldComponent(this, model, format);
  }
}

function fieldComponent(field: Field<typeof Card>, model: Box<Card>, format: Format): ComponentLike<{ Args: {}, Blocks: {} }> {
  let fieldName = field.name as keyof Card;
  let card: typeof Card;
  if (primitive in field.card) {
    card = field.card;
  } else {
    card = model.value[fieldName]?.constructor as typeof Card ?? field.card;
  }
  let innerModel = model.field(fieldName) as unknown as Box<Card>;
  return getBoxComponent(card, format, innerModel);
}

// our decorators are implemented by Babel, not TypeScript, so they have a
// different signature than Typescript thinks they do.
export const field = function(_target: CardConstructor, key: string | symbol, { initializer }: { initializer(): any }) {
  return initializer().setupField(key);
} as unknown as PropertyDecorator;
(field as any)[fieldDecorator] = undefined;

export function containsMany<CardT extends CardConstructor>(cardOrThunk: CardT | (() => CardT), options?: Options): CardInstanceType<CardT>[] {
  return {
    setupField(fieldName: string) {
      return makeDescriptor(new ContainsMany(cardThunk(cardOrThunk), options?.computeVia, fieldName));
    }
  } as any;
}
containsMany[fieldType] = 'contains-many' as FieldType;

export function contains<CardT extends CardConstructor>(cardOrThunk: CardT | (() => CardT), options?: Options): CardInstanceType<CardT> {
  return {
    setupField(fieldName: string) {
      return makeDescriptor(new Contains(cardThunk(cardOrThunk), options?.computeVia, fieldName));
    }
  } as any
}
contains[fieldType] = 'contains' as FieldType;

export function linksTo<CardT extends CardConstructor>(cardOrThunk: CardT | (() => CardT), options?: Options): CardInstanceType<CardT> {
  return {
    setupField(fieldName: string) {
      return makeDescriptor(new LinksTo(cardThunk(cardOrThunk), options?.computeVia, fieldName));
    }
  } as any
}
linksTo[fieldType] = 'linksTo' as FieldType;

export class Card {
  // this is here because Card has no public instance methods, so without it
  // typescript considers everything a valid card.
  [isBaseCard] = true;
  [isSavedInstance] = false;
  declare ["constructor"]: CardConstructor;
  static baseCard: undefined; // like isBaseCard, but for the class itself
  static data?: Record<string, any>;

  static [serialize](value: any, doc: JSONAPISingleResourceDocument, visited?: Set<string>, opts?: { includeComputeds?: boolean}): any {
    if (primitive in this) {
      // primitive cards can override this as need be
      return value;
    } else {
      return serializeCardResource(value, doc, opts, visited);
    }
  }

  static [queryableValue](value: any, linksToDepth = 0): any {
    if (primitive in this) {
      return value;
    } else {
      if (value == null) {
        return null;
      }
      return Object.fromEntries(
        Object.entries(getFields(value, { includeComputeds: true }))
          .map(([fieldName, field]) => {
            let rawValue = peekAtField(value, fieldName);
            if (isNotLoadedValue(rawValue)) {
              return [fieldName, { id: rawValue.reference }];
            }
            let nextLinksToDepth = linksToDepth;
            if (field!.fieldType === 'linksTo') {
              nextLinksToDepth++;
            }
            if (nextLinksToDepth <= maxLinkDepth) {
              return [fieldName, getQueryableValue(field!.card, value[fieldName], nextLinksToDepth)];
            } else if (field!.fieldType === 'linksTo') {
              return [fieldName, { id: value[fieldName].id }];
            } else {
              return [];
            }
          })
      );
    }
  }

  static async [deserialize]<T extends CardConstructor>(this: T, data: any, doc?: CardDocument, identityContext?: IdentityContext): Promise<CardInstanceType<T>> {
    if (primitive in this) {
      // primitive cards can override this as need be
      return data;
    }
    return _createFromSerialized(this, data, doc, identityContext);
  }

  static getComponent(card: Card, format: Format) {
    return getComponent(card, format);
  }

  constructor(data?: Record<string, any>) {
    if (data !== undefined) {
      for (let [fieldName, value] of Object.entries(data)) {
        if (fieldName === 'id') {
          // we need to be careful that we don't trigger the ambient recompute() in our setters
          // when we are instantiating an instance that is placed in the identityMap that has
          // not had it's field values set yet, as computeds will be run that may assume dependent
          // fields are available when they are not (e.g. CatalogEntry.isPrimitive trying to load
          // it's 'ref' field). In this scenario, only the 'id' field is available. the rest of the fields
          // will be filled in later, so just set the 'id' directly in the deserialized cache to avoid
          // triggering the recompute.
          let deserialized = getDataBucket(this);
          deserialized.set('id', value);
        } else {
          (this as any)[fieldName] = value;
        }
      }
    }
  }

  @field id = contains(() => IDCard);
}

export function isCard(card: any): card is Card {
  return card && typeof card === 'object' && isBaseCard in card;
}

export class Component<CardT extends CardConstructor> extends GlimmerComponent<SignatureFor<CardT>> {}

class IDCard extends Card {
  static [primitive]: string;
  static [useIndexBasedKey]: never;
  static embedded = class Embedded extends Component<typeof this> {
    <template>{{@model}}</template>
  }
  static edit = class Edit extends Component<typeof this> {
    <template>
      {{!-- template-lint-disable require-input-label --}}
      <input type="text" value={{@model}} {{on "input" (pick "target.value" @set) }} />
    </template>
  }
}

export type CardConstructor = typeof Card;

function getDataBucket(instance: object): Map<string, any> {
  let deserialized = deserializedData.get(instance);
  if (!deserialized) {
    deserialized = new Map();
    deserializedData.set(instance, deserialized);
  }
  return deserialized;
}

type Scalar = string | number | boolean | null | undefined |
  (string | null | undefined)[] |
  (number | null | undefined)[] |
  (boolean | null | undefined)[] ;

function assertScalar(scalar: any, fieldCard: typeof Card): asserts scalar is Scalar {
  if (Array.isArray(scalar)) {
    if (scalar.find((i) => !['undefined', 'string', 'number', 'boolean'].includes(typeof i) && i !== null)) {
      throw new Error(`expected queryableValue for field type ${fieldCard.name} to be scalar but was ${typeof scalar}`);
    }
  } else if (!['undefined', 'string', 'number', 'boolean'].includes(typeof scalar) && scalar !== null) {
    throw new Error(`expected queryableValue for field type ${fieldCard.name} to be scalar but was ${typeof scalar}`);
  }
}

export function isSaved(instance: Card): boolean {
  return instance[isSavedInstance] === true;
}

export function getQueryableValue(fieldCard: typeof Card, value: any, linksToDepth = 0): any {
  if ((primitive in fieldCard)) {
    let result = (fieldCard as any)[queryableValue](value);
    assertScalar(result, fieldCard);
    return result;
  }
  if (value == null) {
    return null;
  }

  // this recurses through the fields of the compound card via
  // the base card's queryableValue implementation
  return flatten((fieldCard as any)[queryableValue](value, linksToDepth), { safe: true });
}

function peekAtField(instance: Card, fieldName: string): any {
  let field = getField(Reflect.getPrototypeOf(instance)!.constructor as typeof Card, fieldName);
  if (!field) {
    throw new Error(`the card ${instance.constructor.name} does not have a field '${fieldName}'`);
  }
  return getter(instance, field);
}

type RelationshipMeta = NotLoadedRelationship | LoadedRelationship;
interface NotLoadedRelationship {
  type: 'not-loaded';
  reference: string;
  // TODO add a loader (which may turn this into a class)
  // load(): Promise<CardInstanceType<CardT>>;
}
interface LoadedRelationship {
  type: 'loaded';
  card: Card | null;
}

export function relationshipMeta(instance: Card, fieldName: string): RelationshipMeta | undefined {
  let field = getField(Reflect.getPrototypeOf(instance)!.constructor as typeof Card, fieldName);
  if (!field) {
    throw new Error(`the card ${instance.constructor.name} does not have a field '${fieldName}'`);
  }
  if (field.fieldType !== 'linksTo') {
    return undefined;
  }
  let related = getter(instance, field);
  if (isNotLoadedValue(related)) {
    return { type: 'not-loaded', reference: related.reference };
  } else {
    return { type: 'loaded', card: related ?? null };
  }
}

function serializedGet<CardT extends CardConstructor>(
  model: InstanceType<CardT>,
  fieldName: string,
  doc: JSONAPISingleResourceDocument,
  visited: Set<string>
): JSONAPIResource {
  let field = getField(model.constructor, fieldName);
  if (!field) {
    throw new Error(`tried to serializedGet field ${fieldName} which does not exist in card ${model.constructor.name}`);
  }
  return field.serialize(peekAtField(model, fieldName), doc, visited);
}

async function getDeserializedValue<CardT extends CardConstructor>({
  card,
  fieldName,
  value,
  resource,
  modelPromise,
  doc,
  identityContext,
}: {
  card: CardT; 
  fieldName: string; 
  value: any; 
  resource: LooseCardResource;
  modelPromise: Promise<Card>; 
  doc: LooseSingleCardDocument | CardDocument;
  identityContext: IdentityContext;
}): Promise<any> {
  let field = getField(card, fieldName);
  if (!field) {
    throw new Error(`could not find field ${fieldName} in card ${card.name}`);
  }
  let result = await field.deserialize(value, doc, resource.relationships, resource.meta.fields?.[fieldName], identityContext, modelPromise);
  return result;
}

function getExportedAncestorRef(card: typeof Card | null): ExportedCardRef | null {
  if (card == null) {
    return null;
  }
  let adoptsFrom = Loader.identify(card);
  if (!adoptsFrom) {
    let parent = Reflect.getPrototypeOf(card) as typeof Card | null;
    return getExportedAncestorRef(parent);
  }
  return adoptsFrom;
}

function serializeCardResource(
  model: Card,
  doc: JSONAPISingleResourceDocument,
  opts?: {
    includeComputeds?: boolean
  },
  visited: Set<string> = new Set()
): LooseCardResource {
  let adoptsFrom = getExportedAncestorRef(model.constructor);
  if (!adoptsFrom) {
    throw new Error(`bug: encountered a card that has no Loader identity: ${model.constructor.name}`);
  }
  let { id: removedIdField, ...fields } = getFields(model, opts);
  let fieldResources = Object.keys(fields)
    .map(fieldName => serializedGet(model, fieldName, doc, visited));
  return merge({}, ...fieldResources, {
    type: 'card',
    meta: { adoptsFrom }
  }, model.id ? { id: model.id } : undefined);
}

export function serializeCard(
  model: Card,
  opts?: {
    includeComputeds?: boolean
  }
): LooseSingleCardDocument {
  let doc = { data: { type: 'card', ...(model.id != null ? { id: model.id }: {}) } };
  let data = serializeCardResource(model, doc, opts);
  merge(doc, { data });
  if (!isSingleCardDocument(doc)) {
    throw new Error(`Expected serialized card to be a SingleCardDocument, but is was: ${JSON.stringify(doc, null, 2)}`);
  }
  return doc;
}
export async function createFromSerialized<T extends CardConstructor>(
  resource: LooseCardResource,
  doc: LooseSingleCardDocument | CardDocument,
  relativeTo: URL | undefined,
  opts?: { loader?: Loader, identityContext?: IdentityContext },
): Promise<CardInstanceType<T>> {
  let identityContext = opts?.identityContext ?? new IdentityContext();
  let loader = opts?.loader ?? Loader;  
  let { meta: { adoptsFrom } } = resource;
  let module = await loader.import<Record<string, T>>(new URL(adoptsFrom.module, relativeTo).href);
  let card = module[adoptsFrom.name];
  
  return await _createFromSerialized(card, resource as any, doc, identityContext);
}

export async function updateFromSerialized<T extends CardConstructor>(
  instance: CardInstanceType<T>,
  doc: LooseSingleCardDocument,
): Promise<CardInstanceType<T>> {
  let identityContext = identityContexts.get(instance) ?? new IdentityContext();
  return await _updateFromSerialized(instance, doc.data, doc, identityContext);
}

async function _createFromSerialized<T extends CardConstructor>(
  card: T,
  data: T extends { [primitive]: infer P } ? P : LooseCardResource,
  doc: LooseSingleCardDocument | CardDocument | undefined,
  identityContext: IdentityContext = new IdentityContext(),
): Promise<CardInstanceType<T>> {
  if (primitive in card) {
    return card[deserialize](data);
  }
  let resource: LooseCardResource | undefined;
  if (isCardResource(data)) {
    resource = data;
  }
  if (!resource) {
    let adoptsFrom = Loader.identify(card);
    if (!adoptsFrom) {
      throw new Error(`bug: could not determine identity for card '${card.name}'`);
    }
    // in this case we are dealing with an empty instance
    resource = { meta: { adoptsFrom } };
  }
  if (!doc) {
    doc = { data: resource };
  }
  let instance: CardInstanceType<T> | undefined;
  if (resource.id != null) {
    instance = identityContext.identities.get(resource.id) as CardInstanceType<T> | undefined;
  }
  if (!instance) {
    instance = new card({id: resource.id }) as CardInstanceType<T>;
  }
  identityContexts.set(instance, identityContext);
  return await _updateFromSerialized(instance, resource, doc, identityContext);
}

async function _updateFromSerialized<T extends CardConstructor>(
  instance: CardInstanceType<T>,
  resource: LooseCardResource,
  doc: LooseSingleCardDocument | CardDocument,
  identityContext: IdentityContext,
): Promise<CardInstanceType<T>> {
  if (resource.id != null) {
    identityContext.identities.set(resource.id, instance);
  }
  let deferred = new Deferred<Card>();
  let card = Reflect.getPrototypeOf(instance)!.constructor as T;
  let nonNestedRelationships = Object.fromEntries(
    Object.entries(resource.relationships ?? {})
      .filter(([fieldName]) => !fieldName.includes('.'))
    );
  let values = await Promise.all(
    Object.entries({
      ...resource.attributes,
      ...nonNestedRelationships,
      ...(resource.id !== undefined ? { id: resource.id } : {})
    } ?? {}).map(
      async ([fieldName, value]) => {
        let field = getField(card, fieldName);
        if (!field) {
          throw new Error(`could not find field '${fieldName}' in card '${card.name}'`);
        }
        return [
          fieldName,
          await getDeserializedValue({
            card,
            fieldName,
            value,
            resource,
            modelPromise: deferred.promise,
            doc,
            identityContext,
          })
        ];
      }
    )
  ) as [keyof CardInstanceType<T>, any][];

  // this block needs to be synchronous
  {
    let wasSaved = instance[isSavedInstance];
    let originalId = instance.id;
    instance[isSavedInstance] = false;
    for (let [fieldName, value] of values) {
      if (fieldName === 'id' && wasSaved && originalId !== value) {
        throw new Error(`cannot change the id for saved instance ${originalId}`);
      }
      instance[fieldName] = value;
    }
    if (resource.id != null) {
      // importantly, we place this synchronously after the assignment of the model's
      // fields, such that subsequent assignment of the id field when the model is
      // saved will throw
      instance[isSavedInstance] = true;
    }
  }

  deferred.fulfill(instance);
  return instance;
}

export async function searchDoc<CardT extends CardConstructor>(instance: InstanceType<CardT>): Promise<Record<string, any>> {
  await recompute(instance);
  return getQueryableValue(instance.constructor, instance) as Record<string, any>;
}


function makeMetaForField(meta: Partial<Meta> | undefined, fieldName: string, fallback: typeof Card): Meta {
  let adoptsFrom = meta?.adoptsFrom ?? getExportedAncestorRef(fallback);
  if (!adoptsFrom) {
    throw new Error(`bug: cannot determine identity for field '${fieldName}'`);
  }
  let fields: NonNullable<LooseCardResource["meta"]["fields"]> = { ...(meta?.fields ?? {}) };
  return {
    adoptsFrom,
    ...(Object.keys(fields).length > 0 ? { fields } : {})
  };
}

async function cardClassFromResource<CardT extends CardConstructor>(resource: LooseCardResource | undefined, fallback: CardT): Promise<CardT> {
  let cardIdentity = getExportedAncestorRef(fallback);
  if (!cardIdentity) {
    throw new Error(`bug: could not determine identity for card '${fallback.name}'`);
  }
  if (resource && (cardIdentity.module !== resource.meta.adoptsFrom.module || cardIdentity.name !== resource.meta.adoptsFrom.name)) {
    let loader = Loader.getLoaderFor(fallback);
    let module = await loader.import<Record<string, CardT>>(resource.meta.adoptsFrom.module);
    return module[resource.meta.adoptsFrom.name];
  }
  return fallback;
}

function makeDescriptor<CardT extends CardConstructor, FieldT extends CardConstructor>(field: Field<FieldT>) {
  let descriptor: any = {
    enumerable: true,
  };
  descriptor.get = function(this: CardInstanceType<CardT>) {
    return field.getter(this);
  };
  if (field.computeVia) {
    descriptor.set = function() {
      // computeds should just no-op when an assignment occurs
    };
  } else {
    descriptor.set = function(this: CardInstanceType<CardT>, value: any) {
      if (field.card as typeof Card === IDCard && this[isSavedInstance]) {
        throw new Error(`cannot assign a value to the field '${field.name}' on the saved card '${(this as any)[field.name]}' because it is the card's identifier`);
      }
      value = field.validate(this, value);
      let deserialized = getDataBucket(this);
      deserialized.set(field.name, value);
      // invalidate all computed fields because we don't know which ones depend on this one
      for (let computedFieldName of Object.keys(getComputedFields(this))) {
        deserialized.delete(computedFieldName);
      }
      logger.log(recompute(this));
    }
  }
  (descriptor.get as any)[isField] = field;
  return descriptor;
}

function cardThunk<CardT extends CardConstructor>(cardOrThunk: CardT | (() => CardT)): () => CardT {
  return ("baseCard" in cardOrThunk ? () => cardOrThunk : cardOrThunk) as () => CardT;
}

export type SignatureFor<CardT extends CardConstructor> = { Args: { model: PartialCardInstanceType<CardT>; fields: FieldsTypeFor<InstanceType<CardT>>; set: Setter; fieldName: string | undefined } }
 
let defaultStyles = initStyleSheet(`
  this {
    border: 1px solid gray;
    border-radius: 10px;
    background-color: #e9e7e7;
    padding: 1rem;
  }
`);
let editStyles = initStyleSheet(`
  this {
    border: 1px solid gray;
    border-radius: 10px;
    background-color: #e9e7e7;
    padding: 1rem;
  }
  .edit-field {
    display: block;
    padding: 0.75rem;
    text-transform: capitalize;
    background-color: #ffffff6e;
    border: 1px solid gray;
    margin: 0.5rem 0;
  }
  input[type=text],
  input[type=number] {
    box-sizing: border-box;
    background-color: transparent;
    width: 100%;
    margin-top: .5rem;
    display: block;
    padding: 0.5rem;
    font: inherit;
    border: inherit;
  }
  textarea {
    box-sizing: border-box;
    background-color: transparent;
    width: 100%;
    min-height: 5rem;
    margin-top: .5rem;
    display: block;
    padding: 0.5rem;
    font: inherit;
    border: inherit;
  }
`);

class DefaultIsolated extends GlimmerComponent<{ Args: { model: Card; fields: Record<string, new() => GlimmerComponent>}}> {
  <template>
    <div {{attachStyles defaultStyles}}>
      {{#each-in @fields as |key Field|}}
        {{#unless (eq key 'id')}}
          <Field />
        {{/unless}}
      {{/each-in}}
    </div>
  </template>;
}

class DefaultEdit extends GlimmerComponent<{ Args: { model: Card; fields: Record<string, new() => GlimmerComponent>}}> {
  <template>
    <div {{attachStyles editStyles}}>
      {{#each-in @fields as |key Field|}}
        {{#unless (eq key 'id')}}
          <label class="edit-field" data-test-field={{key}}>
            {{!-- @glint-ignore glint is arriving at an incorrect type signature --}}
            {{startCase key}}
            <Field />
          </label>
        {{/unless}}
      {{/each-in}}
    </div>
  </template>;
}

const defaultComponent = {
  embedded: <template><!-- Inherited from base card embedded view. Did your card forget to specify its embedded component? --></template>,
  isolated: DefaultIsolated,
  edit: DefaultEdit,
}

function defaultFieldFormat(format: Format): Format {
  switch (format) {
    case 'edit':
      return 'edit';
    case 'isolated':
    case 'embedded':
      return 'embedded';
  }
}

function getBoxComponent<CardT extends CardConstructor>(card: CardT, format: Format, model: Box<InstanceType<CardT>>): ComponentLike<{ Args: {}, Blocks: {} }> {
  let stable = componentCache.get(model);
  if (stable) {
    return stable;
  }

  let Implementation = (card as any)[format] ?? defaultComponent[format];

  // *inside* our own component, @fields is a proxy object that looks
  // up our fields on demand.
  let internalFields = fieldsComponentsFor({}, model, defaultFieldFormat(format));
  
  let isPrimitive = primitive in card;
  let component: ComponentLike<{ Args: {}, Blocks: {} }> = <template>
    {{#if isPrimitive}}
      <Implementation @model={{model.value}} @fields={{internalFields}} @set={{model.set}} @fieldName={{model.name}} />
    {{else}}
      <ShadowDOM>
        <Implementation @model={{model.value}} @fields={{internalFields}} @set={{model.set}} @fieldName={{model.name}} />
      </ShadowDOM>
    {{/if}}
  </template>

  // when viewed from *outside*, our component is both an invokable component
  // and a proxy that makes our fields available for nested invocation, like
  // <@fields.us.deeper />.
  //
  // It would be possible to use `externalFields` in place of `internalFields` above,
  // avoiding the need for two separate Proxies. But that has the uncanny property of
  // making `<@fields />` be an infinite recursion.
  let externalFields = fieldsComponentsFor(component, model, defaultFieldFormat(format));


  // This cast is safe because we're returning a proxy that wraps component.
  stable = externalFields as unknown as typeof component;
  componentCache.set(model, stable);
  return stable;
}

export function getComponent(model: Card, format: Format): ComponentLike<{ Args: {}, Blocks: {} }> {
  let box = Box.create(model);
  let component = getBoxComponent(model.constructor as CardConstructor, format, box);
  return component;
}

interface RecomputeOptions {
  loadFields?: true;
}
export async function recompute(card: Card, opts?: RecomputeOptions): Promise<void> {
  // Note that after each async step we check to see if we are still the
  // current promise, otherwise we bail
  let done: () => void;
  let recomputePromise = new Promise<void>((res) => (done = res));
  recomputePromises.set(card, recomputePromise);

  // wait a full micro task before we start - this is simple debounce
  await Promise.resolve();
  if (recomputePromises.get(card) !== recomputePromise) {
    return;
  }

  async function _loadModel<T extends Card>(model: T, stack: Card[] = []): Promise<void> {
    for (let fieldName of Object.keys(getFields(model, { includeComputeds: true }))) {
      let value: any = await loadField(model, fieldName as keyof T, opts);
      if (recomputePromises.get(card) !== recomputePromise) {
        return;
      }
      if (isCard(value) && !stack.includes(value)) {
        await _loadModel(value, [value, ...stack]);
      }
    }
  }

  await _loadModel(card);
  if (recomputePromises.get(card) !== recomputePromise) {
    return;
  }

  // notify glimmer to rerender this card
  cardTracking.set(card, true);
  done!();
}

async function loadField<T extends Card, K extends keyof T>(model: T, fieldName: K, opts?: RecomputeOptions): Promise<T[K]> {
  let result: T[K];
  let isLoaded = false;
  let deserialized = getDataBucket(model);
  let identityContext = identityContexts.get(model) ?? new IdentityContext();
  while(!isLoaded) {
    try {
      result = model[fieldName];
      isLoaded = true;
    } catch (e: any) {
      if (isNotLoadedError(e)) {
        // taking advantage of the identityMap regardless of whether loadFields is set
        let instance = identityContext.identities.get(e.reference);
        if (instance) {
          deserialized.set(fieldName as string, instance);
          continue;
        }

        if (opts?.loadFields) {
          let card = Reflect.getPrototypeOf(model)!.constructor as typeof Card;
          let field = getField(card, fieldName as string);
          if (!field) {
            throw new Error(`the field '${fieldName as string} does not exist in card ${card.name}'`);
          }
          let instance = await loadMissingField(card, field, e, identityContext);
          deserialized.set(fieldName as string, instance);
        } else {
          isLoaded = true;
        }
      } else if (isNotReadyError(e)) {
        let { model: depModel, computeVia, fieldName: depField } = e;
        if (typeof computeVia === 'function') {
          deserialized.set(depField, await computeVia.bind(depModel)());
        } else {
          deserialized.set(depField, await depModel[computeVia]());
        }
      } else {
        throw e;
      }
    }
  }
  // case OK because deserialized.set assigns it
  return result!;
}

async function loadMissingField(
  card: typeof Card,
  field: Field<typeof Card>,
  notLoaded: NotLoadedValue | NotLoaded,
  identityContext: IdentityContext,
): Promise<Card> {
  if (field.fieldType !== "linksTo") {
    throw new Error(`cannot load missing field for non-linksTo field ${card.name}.${field.name}`);
  }
  let { reference } = notLoaded;
  let loader = Loader.getLoaderFor(createFromSerialized);
  let response = await loader.fetch(reference, { headers: { 'Accept': 'application/vnd.api+json' } });
  if (!response.ok) {
    let cardError = await CardError.fromFetchResponse(reference, response);
    cardError.deps = [reference];
    cardError.additionalErrors = [new NotLoaded(reference, field.name, card.name)];
    throw cardError;
  }
  let json = await response.json();
  if (!isSingleCardDocument(json)) {
    throw new Error(`instance ${reference} is not a card document. it is: ${JSON.stringify(json, null, 2)}`);
  }
  let instance = await createFromSerialized(json.data, json, undefined, { loader, identityContext });
  return instance;
}


export function getField<CardT extends CardConstructor>(card: CardT, fieldName: string): Field<CardConstructor> | undefined {
  let obj: object | null = card.prototype;
  while (obj) {
    let desc = Reflect.getOwnPropertyDescriptor(obj, fieldName);
    let result = (desc?.get as any)?.[isField];
    if (result !== undefined) {
      return result;
    }
    obj = Reflect.getPrototypeOf(obj);
  }
  return undefined;
}

export function getFields(card: typeof Card, opts?: { includeComputeds?: boolean }): { [fieldName: string]: Field<CardConstructor> };
export function getFields<T extends Card>(card: T, opts?: { includeComputeds?: boolean }): { [P in keyof T]?: Field<CardConstructor> };
export function getFields(cardInstanceOrClass: Card | typeof Card, opts?: { includeComputeds?: boolean }): { [fieldName: string]: Field<CardConstructor> } {
  let obj: object | null;
  if (isCard(cardInstanceOrClass)) {
    // this is a card instance
    obj = Reflect.getPrototypeOf(cardInstanceOrClass);
  } else {
    // this is a card class
    obj = (cardInstanceOrClass as typeof Card).prototype;
  }
  let fields: { [fieldName: string]: Field<CardConstructor> } = {};
  while (obj?.constructor.name && obj.constructor.name !== 'Object') {
    let descs = Object.getOwnPropertyDescriptors(obj);
    let currentFields = flatMap(Object.keys(descs), maybeFieldName => {
      if (maybeFieldName !== 'constructor') {
        let maybeField = getField((isCard(cardInstanceOrClass) ? cardInstanceOrClass.constructor : cardInstanceOrClass) as typeof Card, maybeFieldName);
        if (maybeField?.computeVia && !opts?.includeComputeds) {
          return [];
        }
        if (maybeField) {
          return [[maybeFieldName, maybeField]];
        }
      }
      return [];
    });
    fields = { ...fields, ...Object.fromEntries(currentFields) };
    obj = Reflect.getPrototypeOf(obj);
  }
  return fields;
}

function getComputedFields<T extends Card>(card: T): { [P in keyof T]?: Field<CardConstructor> } {
  let fields = Object.entries(getFields(card, { includeComputeds: true })) as [string, Field<CardConstructor>][];
  let computedFields = fields.filter(([_, field]) => field.computeVia);
  return Object.fromEntries(computedFields) as { [P in keyof T]?: Field<CardConstructor> };
}

function fieldsComponentsFor<T extends Card>(target: object, model: Box<T>, defaultFormat: Format): FieldsTypeFor<T> {
  return new Proxy(target, {
    get(target, property, received) {
      if (typeof property === 'symbol' || model == null || model.value == null) {
        // don't handle symbols or nulls
        return Reflect.get(target, property, received);
      }
      let modelValue = model.value as T; // TS is not picking up the fact we already filtered out nulls and undefined above
      let maybeField = getField(modelValue.constructor, property);
      if (!maybeField) {
        // field doesn't exist, fall back to normal property access behavior
        return Reflect.get(target, property, received);
      }
      let field = maybeField;
      defaultFormat = getField(modelValue.constructor, property)?.computeVia ? 'embedded' : defaultFormat;
      return field.component(model, defaultFormat);
    },
    getPrototypeOf() {
      // This is necessary for Ember to be able to locate the template associated
      // with a proxied component. Our Proxy object won't be in the template WeakMap,
      // but we can pretend our Proxy object inherits from the true component, and
      // Ember's template lookup respects inheritance.
      return target;
    },
    ownKeys(target)  {
      let keys = Reflect.ownKeys(target);
      for (let name in model.value) {
        let field = getField(model.value.constructor, name);
        if (field) {
          keys.push(name);
        }
      }
      return keys;
    },
    getOwnPropertyDescriptor(target, property) {
      if (typeof property === 'symbol' || model == null || model.value == null) {
        // don't handle symbols, undefined, or nulls
        return Reflect.getOwnPropertyDescriptor(target, property);
      }
      let field = getField(model.value.constructor, property);
      if (!field) {
        // field doesn't exist, fall back to normal property access behavior
        return Reflect.getOwnPropertyDescriptor(target, property);
      }
      // found field: fields are enumerable properties
      return {
        enumerable: true,
        writable: true,
        configurable: true,
      }
    },

  }) as any;
}

export class Box<T> {
  static create<T>(model: T): Box<T> {
    return new Box({ type: 'root', model });
  }

  private state:
    {
      type: 'root';
      model: any
    } |
    {
      type: 'derived';
      containingBox: Box<any>;
      fieldName: string | number| symbol;
      useIndexBasedKeys: boolean;
    };

  private constructor(state: Box<T>["state"]) {
    this.state = state;
  }

  get value(): T {
    if (this.state.type === 'root') {
      return this.state.model;
    } else {
      return this.state.containingBox.value[this.state.fieldName];
    }
  }

  get containingBoxType() {
    if (this.state.type === 'root') {
      return undefined;
    } else {
      return this.state.containingBox.value.constructor;
    }
  }

  get name() {
    return this.state.type === 'derived' ? this.state.fieldName : undefined;
  }

  set value(v: T) {
    if (this.state.type === 'root') {
      throw new Error(`can't set topmost model`);
    } else {
      let value = this.state.containingBox.value;
      if (Array.isArray(value) && typeof this.state.fieldName !== 'number') {
        throw new Error(`Cannot set a value on an array item with non-numeric index '${String(this.state.fieldName)}'`);
      }
      this.state.containingBox.value[this.state.fieldName] = v;
    }
  }

  set = (value: T): void => { this.value = value; }

  private fieldBoxes = new Map<string, Box<unknown>>();

  field<K extends keyof T>(fieldName: K, useIndexBasedKeys = false): Box<T[K]> {
    let box = this.fieldBoxes.get(fieldName as string);
    if (!box) {
      box = new Box({
        type: 'derived',
        containingBox: this,
        fieldName,
        useIndexBasedKeys,
      });
      this.fieldBoxes.set(fieldName as string, box);
    }
    return box as Box<T[K]>;
  }

  private prevChildren: Box<ElementType<T>>[] = [];

  get children(): Box<ElementType<T>>[] {
    if (this.state.type === 'root') {
      throw new Error('tried to call children() on root box');
    }
    let value = this.value;
    if (!Array.isArray(value)) {
      throw new Error(`tried to call children() on Boxed non-array value ${value} for ${String(this.state.fieldName)}`);
    }

    let { prevChildren, state } = this;
    let newChildren: Box<ElementType<T>>[] = value.map((element, index) => {
      let found = prevChildren.find((oldBox, i) => (state.useIndexBasedKeys ? index === i : oldBox.value === element));
      if (found) {
        if (state.useIndexBasedKeys) {
          // note that the underlying box already has the correct value so there
          // is nothing to do in this case. also, we are currently inside a rerender.
          // mutating a watched array in a rerender will spawn another rerender which
          // infinitely recurses.
        } else {
          prevChildren.splice(prevChildren.indexOf(found), 1);
          if (found.state.type === 'root') {
            throw new Error('bug');
          }
          found.state.fieldName = index;
        }
        return found;
      } else {
        return new Box({
          type: 'derived',
          containingBox: this,
          fieldName: index,
          useIndexBasedKeys: false,
        });
      }
    });
    this.prevChildren = newChildren;
    return newChildren;
  }
}

type ElementType<T> = T extends (infer V)[] ? V : never;  

function eq<T>(a: T, b: T, _namedArgs: unknown): boolean {
  return a === b;
}

interface ContainsManySignature {
  Args: {
    model: Box<Card>;
    arrayField: Box<Card[]>;
    format: Format;
    field: Field<typeof Card>;
  };
}

class ContainsManyEditor extends GlimmerComponent<ContainsManySignature> {
  <template>
    <section data-test-contains-many={{this.args.field.name}}>
      <ul>
        {{#each @arrayField.children as |boxedElement i|}}
          <li data-test-item={{i}}>
            {{#let (getBoxComponent (cardTypeFor @field boxedElement) @format boxedElement) as |Item|}}
              <Item />
            {{/let}}
            <button {{on "click" (fn this.remove i)}} type="button" data-test-remove={{i}}>Remove</button>
          </li>
        {{/each}}
      </ul>
      <button {{on "click" this.add}} type="button" data-test-add-new>Add New</button>
    </section>
  </template>

  add = () => {
    // TODO probably each field card should have the ability to say what a new item should be
    let newValue = primitive in this.args.field.card ? null : new this.args.field.card();
    (this.args.model.value as any)[this.args.field.name].push(newValue);
  }

  remove = (index: number) => {
    (this.args.model.value as any)[this.args.field.name].splice(index, 1);
  }
}

interface LinksToEditorSignature {
  Args: {
    model: Box<Card | null>;
    field: Field<typeof Card>;
  }
}

let linksToEditorStyles = initStyleSheet(`
  this { 
    background-color: #fff; 
    border: 1px solid #ddd;
    border-radius: 20px; 
    padding: 1rem; 
  }
  button {
    margin-top: 1rem;
    font: inherit;
    font-weight: 600;
    border: none;
    background-color: white;
    padding: 0.5em 0;
    text-transform: capitalize;
  }
  button:hover {
    color: #00EBE5;
  }
`);
class LinksToEditor extends GlimmerComponent<LinksToEditorSignature> {
  <template>
    <div {{attachStyles linksToEditorStyles}}>
      {{#if this.isEmpty}}
        <div data-test-empty-link>{{!-- PLACEHOLDER CONTENT --}}</div>
        <button {{on "click" this.choose}} data-test-choose-card>
          + Add {{@field.name}}
        </button>
      {{else}}
        <this.linkedCard/>
        <button {{on "click" this.remove}} data-test-remove-card disabled={{this.isEmpty}}>
          Remove {{@field.name}}
        </button>
      {{/if}}
    </div>
  </template>

  choose = () => {
    taskFor(this.chooseCard).perform();
  }

  remove = () => {
    this.args.model.value = null;
  }

  get isEmpty() {
    return this.args.model.value == null;
  }

  get linkedCard() {
    if (this.args.model.value == null) {
      throw new Error(`can't make field component with box value of null for field ${field.name}`);
    }
    let card = Reflect.getPrototypeOf(this.args.model.value)!.constructor as typeof Card;
    return getBoxComponent(card, 'embedded', this.args.model as Box<Card>);
  }

  @restartableTask private async chooseCard(this: LinksToEditor) {
    let type = Loader.identify(this.args.field.card);
    if (!type) {
      let containingType = Loader.identify(this.args.model.containingBoxType);
      type = containingType?.module ? {
        module: containingType.module,
        name: this.args.field.card.name,
      } : baseCardRef;
    }
    let chosenCard = await chooseCard(
      { filter: { type }},
      { offerToCreate: type }
    );
    if (chosenCard) {
      this.args.model.value = chosenCard;
    }
  }
};