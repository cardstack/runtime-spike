import GlimmerComponent from '@glimmer/component';
import { ComponentLike } from '@glint/template';
import { NotReady, isNotReadyError} from './not-ready';
import { flatMap, startCase, get, merge } from 'lodash';
import { TrackedWeakMap } from 'tracked-built-ins';
import { registerDestructor } from '@ember/destroyable';
import { WatchedArray } from './watched-array';
import { flatten } from "flat";
import { on } from '@ember/modifier';
import { pick } from './pick';
import ShadowDOM from 'https://cardstack.com/base/shadow-dom';
import { initStyleSheet, attachStyles } from 'https://cardstack.com/base/attach-styles';
import {
  Deferred,
  isCardResource,
  Loader,
  isSingleCardDocument,
  type Relationship,
  type LooseCardResource,
  type LooseSingleCardDocument
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

const deserializedData = new WeakMap<object, Map<string, any>>();
const recomputePromises = new WeakMap<Card, Promise<any>>();
const componentCache = new WeakMap<Box<unknown>, ComponentLike<{ Args: {}; Blocks: {}; }>>();

// our place for notifying Glimmer when a card is ready to re-render (which will
// involve rerunning async computed fields)
const cardTracking = new TrackedWeakMap<object, any>();

const isBaseCard = Symbol('isBaseCard');

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
  serialize(value: any, doc: JSONAPISingleResourceDocument): JSONAPIResource;
  deserialize(value: any, fromResource: LooseCardResource | undefined, instancePromise: Promise<Card>): Promise<any>;
  emptyValue(instance: Card): any;
  validate(instance: Card, value: any): void;
  component(model: Box<Card>, format: Format): ComponentLike<{ Args: {}, Blocks: {} }>;
}

function callSerializeHook(card: typeof Card, value: any, doc: JSONAPISingleResourceDocument) {
  if (value !== null) {
    return card[serialize](value, doc);
  } else {
    return null;
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

  serialize(values: CardInstanceType<FieldT>[], doc: JSONAPISingleResourceDocument){
    if (primitive in this.card) {
      return { attributes: { [this.name]:  values.map(value => callSerializeHook(this.card, value, doc)) } };
    } else {
      let serialized = values.map(value => {
        let resource: JSONAPIResource = callSerializeHook(this.card, value, doc);
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

  async deserialize(value: any[], fromResource: LooseCardResource | undefined, instancePromise: Promise<Card>): Promise<CardInstanceType<FieldT>[]> {
    if (!Array.isArray(value)) {
      throw new Error(`Expected array for field value ${this.name}`);
    }
    return new WatchedArray(
      () => instancePromise.then(instance => recompute(instance)),
      await Promise.all(value.map(async (entry, index) => {
        if (isCardResource(fromResource)) {
          entry = hydrateField(fromResource, `${this.name}.${index}`, this.card);
        }
        return (await cardClassFromData(entry, this.card))[deserialize](entry);
      }))
    );
  }

  emptyValue(instance: Card) { return new WatchedArray(() => recompute(instance)) }

  validate(instance: Card, value: any) {
    if (value && !Array.isArray(value)) {
      throw new Error(`Expected array for field value ${this.name}`);
    }
    return new WatchedArray(() => recompute(instance), value);
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
            @fieldName={{fieldName}}
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
          {{#let (getComponent (cardTypeFor field boxedElement) format boxedElement) as |Item|}}
            <Item/>
          {{/let}}
        {{/each}}
      </template>
    };
  }
}

function cardTypeFor(field: Field<typeof Card>, boxedElement: Box<Card>): typeof Card {
  if (primitive in field.card) {
      return field.card;
  }
  return Reflect.getPrototypeOf(boxedElement.value)!.constructor as typeof Card;
}

class Contains<CardT extends CardConstructor> implements Field<CardT> {
  readonly fieldType = 'contains';
  constructor(private cardThunk: () => CardT, readonly computeVia: undefined | string | (() => unknown), readonly name: string) {
  }

  get card(): CardT {
    return this.cardThunk();
  }

  serialize(value: InstanceType<CardT>, doc: JSONAPISingleResourceDocument) {
    let serialized = callSerializeHook(this.card, value, doc);
    if (primitive in this.card) {
      return { attributes: { [this.name]: serialized } }
    } else {
      let resource: JSONAPIResource = { 
        attributes: { 
          [this.name]: serialized.attributes 
        }
      };

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

  async deserialize(value: any, fromResource: LooseCardResource | undefined): Promise<CardInstanceType<CardT>> {
    if (isCardResource(fromResource)) {
      value = hydrateField(fromResource, this.name, this.card);
    }
    return (await cardClassFromData(value, this.card))[deserialize](value);
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

  component(model: Box<Card>, format: Format) {
    let fieldName = this.name as keyof Card;
    let card: typeof Card;
    if (primitive in this.card) {
      card = this.card;
    } else {
      card = model.value[fieldName].constructor as typeof Card;
    }
    let innerModel = model.field(fieldName) as unknown as Box<Card>;
    return getComponent(card, format, innerModel);
  }
}

class LinksTo<CardT extends CardConstructor> implements Field<CardT> {
  readonly fieldType = 'linksTo';
  constructor(private cardThunk: () => CardT, readonly computeVia: undefined | string | (() => unknown), readonly name: string) {
  }

  get card(): CardT {
    return this.cardThunk();
  }

  serialize(value: InstanceType<CardT>, doc: JSONAPISingleResourceDocument) {
    let serialized = callSerializeHook(this.card, value, doc) as (JSONAPIResource & { id: string; type: string }) | null;
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
      doc.included = doc.included ?? [];
      doc.included.push(serialized);
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

  async deserialize(_value: any, _fromResource: LooseCardResource | undefined): Promise<CardInstanceType<CardT>> {
    throw new Error('not implemented');
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
      if (!(value instanceof this.card)) {
        throw new Error(`tried set ${value} as field '${this.name}' but it is not an instance of ${this.card.name}`);
      }
    }
    return value;
  }

  component(_model: Box<Card>, _format: Format): ComponentLike<{ Args: {}, Blocks: {} }> {
    throw new Error('not implemented');
  }
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

  static [serialize](value: any, doc: JSONAPISingleResourceDocument, opts?: { includeComputeds?: boolean}): any {
    if (primitive in this) {
      // primitive cards can override this as need be
      return value;
    } else {
      return serializeCardResource(value, doc, opts);
    }
  }

  static [queryableValue](value: any): any {
    if (primitive in this) {
      return value;
    } else {
      return Object.fromEntries(
        Object.entries(getFields(value, { includeComputeds: true })).map(([fieldName, field]) => [fieldName, getQueryableValue(field!.card, value[fieldName])])
      );
    }
  }

  static async [deserialize]<T extends CardConstructor>(this: T, data: any): Promise<CardInstanceType<T>> {
    if (primitive in this) {
      // primitive cards can override this as need be
      return data;
    }
    return createFromSerialized(this, data);
  }

  static async didRecompute(card: Card): Promise<void> {
    let promise = recomputePromises.get(card);
    await promise;
  }

  constructor(data?: Record<string, any>) {
    if (data !== undefined) {
      for (let [fieldName, value] of Object.entries(data)) {
        (this as any)[fieldName] = value;
      }
    }

    registerDestructor(this, Card.didRecompute.bind(this));
  }

  @field id = contains(() => IDCard);
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

export function getQueryableValue(fieldCard: typeof Card, value: any): any {
  if ((primitive in fieldCard)) {
    let result = (fieldCard as any)[queryableValue](value);
    assertScalar(result, fieldCard);
    return result;
  }

  // this recurses through the fields of the compound card via
  // the base card's queryableValue implementation
  return flatten((fieldCard as any)[queryableValue](value), { safe: true });
}

function serializedGet<CardT extends CardConstructor>(
  model: InstanceType<CardT>,
  fieldName: string,
  doc: JSONAPISingleResourceDocument,
): JSONAPIResource {
  let field = getField(model.constructor, fieldName);
  if (!field) {
    throw new Error(`tried to serializedGet field ${fieldName} which does not exist in card ${model.constructor.name}`);
  }
  return field.serialize((model as any)[fieldName], doc);
}

async function getDeserializedValues<CardT extends CardConstructor>(card: CardT, fieldName: string, value: any, modelPromise: Promise<Card>, fromResource: LooseCardResource | undefined): Promise<any> {
  let field = getField(card, fieldName);
  if (!field) {
    throw new Error(`could not find field ${fieldName} in card ${card.name}`);
  }
  return await field.deserialize(value, fromResource, modelPromise);
}

function serializeCardResource(
  model: Card,
  doc: JSONAPISingleResourceDocument,
  opts?: {
    includeComputeds?: boolean
  }
): LooseCardResource {
  let adoptsFrom = Loader.identify(model.constructor);
  if (!adoptsFrom) {
    throw new Error(`bug: encountered a card that has no Loader identity: ${model.constructor.name}`);
  }
  let { id: removedIdField, ...fields } = getFields(model, opts);
  let fieldResources = Object.keys(fields)
    .filter(fieldName => model[fieldName as keyof typeof model] !== undefined) // skip over missing fields
    .map(fieldName => serializedGet(model, fieldName, doc));
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
  let doc = { data: { type: 'card' } };
  let data = serializeCardResource(model, doc, opts);
  merge(doc, { data });
  if (!isSingleCardDocument(doc)) {
    throw new Error(`Expected serialized card to be a SingleCardDocument, but is was: ${JSON.stringify(doc, null, 2)}`);
  }
  return doc;
}

export async function createFromSerialized<T extends CardConstructor>(CardClass: T, data: T extends { [primitive]: infer P } ? P : LooseCardResource, opts?: { loader?: Loader }): Promise<CardInstanceType<T>>;
export async function createFromSerialized<T extends CardConstructor>(resource: LooseCardResource, relativeTo: URL | undefined, opts?: { loader?: Loader}): Promise<CardInstanceType<T>>;
export async function createFromSerialized<T extends CardConstructor>(CardClassOrResource: T | LooseCardResource, dataOrRelativeTo?: any | URL, opts?: { loader?: Loader }): Promise<CardInstanceType<T>> {
  let CardClass: T;
  let resource: any;
  let loader = opts?.loader ?? Loader;
  if (isCardResource(CardClassOrResource)){
    let relativeTo = dataOrRelativeTo instanceof URL ? dataOrRelativeTo : undefined;
    let { meta: { adoptsFrom } } = CardClassOrResource;
    let module = await loader.import<Record<string, T>>(new URL(adoptsFrom.module, relativeTo).href);
    CardClass = module[adoptsFrom.name];
    resource = CardClassOrResource;
  } else if ("baseCard" in CardClassOrResource) {
    CardClass = CardClassOrResource;
    resource = dataOrRelativeTo;
  } else {
    throw new Error(`don't know how to serialize ${JSON.stringify(CardClassOrResource, null, 2)}`);
  }

  if (primitive in CardClass) {
    return CardClass[deserialize](resource);
  }
  if (!isCardResource(resource)) {
    throw new Error(`the provided serialized data is not a card resource: ${JSON.stringify(resource)}`);
  }
  return await updateFromSerialized(new CardClass() as CardInstanceType<T>, resource);
}

export async function updateFromSerialized<T extends CardConstructor>(instance: CardInstanceType<T>, resource: LooseCardResource): Promise<CardInstanceType<T>> {
  let deferred = new Deferred<Card>();
  let CardClass = Reflect.getPrototypeOf(instance)!.constructor as T;
  let values = await Promise.all(
    Object.entries({
      ...resource.attributes,
      ...(resource.id !== undefined ? { id: resource.id } : {})
    } ?? {}).map(
      async ([fieldName, value]) => {
        let field = getField(CardClass, fieldName);
        if (!field) {
          throw new Error(`could not find field '${fieldName}' in card '${CardClass.name}'`);
        }
        return [
          fieldName,
          await getDeserializedValues(
            CardClass,
            fieldName,
            value,
            deferred.promise,
            primitive in field.card ? undefined : resource
          )
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

export async function searchDoc<CardT extends CardConstructor>(model: InstanceType<CardT>): Promise<Record<string, any>> {
  await recompute(model);
  return getQueryableValue(model.constructor, model) as Record<string, any>;
}


function hydrateField(resource: LooseCardResource, fieldName: string, fallback: typeof Card): LooseCardResource {
  let adoptsFrom = get(resource, `meta.fields.${fieldName}.adoptsFrom`) ?? Loader.identify(fallback);
  if (!adoptsFrom) {
    throw new Error(`bug: cannot determine identity for field '${fieldName}'`);
  }
  let fields: NonNullable<LooseCardResource["meta"]["fields"]> = {
    ...(get(resource, `meta.fields.${fieldName}.fields`) ?? {})
  };
  return {
    attributes: get(resource, `attributes.${fieldName}`) ?? {},
    meta: {
      adoptsFrom,
      ...(Object.keys(fields).length > 0 ? { fields } : {})
    }
  };
}

async function cardClassFromData<CardT extends CardConstructor>(value: any, fallback: CardT): Promise<CardT> {
  if (isCardResource(value)) {
    let cardIdentity = Loader.identify(fallback);
    if (!cardIdentity) {
      throw new Error(`bug: could not determine identity for card '${fallback.name}'`);
    }
    if (cardIdentity.module !== value.meta.adoptsFrom.module || cardIdentity.name !== value.meta.adoptsFrom.name) {
      let loader = Loader.getLoaderFor(fallback);
      let module = await loader.import<Record<string, CardT>>(value.meta.adoptsFrom.module);
      return module[value.meta.adoptsFrom.name];
    }
  }
  return fallback;
}

function makeDescriptor<CardT extends CardConstructor, FieldT extends CardConstructor>(field: Field<FieldT>) {
  let descriptor: any = {
    enumerable: true,
  };
  if (field.computeVia) {
    descriptor.get = function(this: CardInstanceType<CardT>) {
      let deserialized = getDataBucket(this);
      // this establishes that our field should rerender when cardTracking for this card changes
      cardTracking.get(this);
      let value = deserialized.get(field.name);
      if (value === undefined && typeof field.computeVia === 'function' && field.computeVia.constructor.name !== 'AsyncFunction') {
        value = field.computeVia.bind(this)();
        deserialized.set(field.name, value);
      } else if (value === undefined && (typeof field.computeVia === 'string' || typeof field.computeVia === 'function')) {
        throw new NotReady(this, field.name, field.computeVia, this.constructor.name);
      }
      return value;
    };
    descriptor.set = function() {
      // computeds should just no-op when an assignment occurs
    };
  } else {
    descriptor.get = function(this: CardInstanceType<CardT>) {
      let deserialized = getDataBucket(this);
      // this establishes that our field should rerender when cardTracking for this card changes
      cardTracking.get(this);
      if (deserialized.has(field.name)) {
        return deserialized.get(field.name);
      }
      let value = field.emptyValue(this);
      deserialized.set(field.name, value);
      return value;
    }
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
      (async () => await recompute(this))();
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
      {{#each-in @fields as |_key Field|}}
        <Field />
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

function getComponent<CardT extends CardConstructor>(card: CardT, format: Format, model: Box<InstanceType<CardT>>): ComponentLike<{ Args: {}, Blocks: {} }> {
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

export async function prepareToRender(model: Card, format: Format): Promise<{ component: ComponentLike<{ Args: never, Blocks: never }> }> {
  await recompute(model); // absorb model asynchronicity
  let box = Box.create(model);
  let component = getComponent(model.constructor as CardConstructor, format, box);
  return { component };
}

export async function recompute(card: Card): Promise<void> {
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

  async function _loadModel<T extends Card>(model: T, stack: { from: T, to: T, name: string}[] = []): Promise<void> {
    for (let [fieldName, field] of Object.entries(getFields(model, { includeComputeds: true }))) {
      let value: any = await loadField(model, fieldName as keyof T);
      if (recomputePromises.get(card) !== recomputePromise) {
        return;
      }
      if (!(primitive in field.card) && value != null &&
        !stack.find(({ from, to, name }) => from === model && to === value && name === fieldName)
      ) {
        await _loadModel(value, [...stack, { from: model, to: value, name: fieldName }]);
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

async function loadField<T extends Card, K extends keyof T>(model: T, fieldName: K): Promise<T[K]> {
  let result: T[K];
  let isLoaded = false;
  let deserialized = getDataBucket(model);
  while(!isLoaded) {
    try {
      result = model[fieldName];
      isLoaded = true;
    } catch (e: any) {
      if (!isNotReadyError(e)) {
        throw e;
      }
      let { model, computeVia, fieldName } = e;
      if (typeof computeVia === 'function') {
        deserialized.set(fieldName, await computeVia.bind(model)());
      } else {
        deserialized.set(fieldName, await model[computeVia]());
      }
    }
  }
  // case OK because deserialized.set assigns it
  return result!;
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
  if (isBaseCard in cardInstanceOrClass) {
    // this is a card instance
    obj = Reflect.getPrototypeOf(cardInstanceOrClass as Card);
  } else {
    // this is a card class
    obj = (cardInstanceOrClass as typeof Card).prototype;
  }
  let fields: { [fieldName: string]: Field<CardConstructor> } = {};
  while (obj?.constructor.name && obj.constructor.name !== 'Object') {
    let descs = Object.getOwnPropertyDescriptors(obj);
    let currentFields = flatMap(Object.keys(descs), maybeFieldName => {
      if (maybeFieldName !== 'constructor') {
        let maybeField = getField((isBaseCard in cardInstanceOrClass ? cardInstanceOrClass.constructor : cardInstanceOrClass) as typeof Card, maybeFieldName);
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

import { action } from '@ember/object';
import { fn } from '@ember/helper';

interface ContainsManySignature {
  Args: {
    model: Box<Card>,
    fieldName: keyof Card,
    arrayField: Box<Card[]>,
    format: Format;
    field: Field<typeof Card>;
  };
}

class ContainsManyEditor extends GlimmerComponent<ContainsManySignature> {
  <template>
    <section data-test-contains-many={{this.safeFieldName}}>
      <header>{{this.safeFieldName}}</header>
      <ul>
        {{#each @arrayField.children as |boxedElement i|}}
          <li data-test-item={{i}}>
            {{#let (getComponent (cardTypeFor @field boxedElement) @format boxedElement) as |Item|}}
              <Item />
            {{/let}}
            <button {{on "click" (fn this.remove i)}} type="button" data-test-remove={{i}}>Remove</button>
          </li>
        {{/each}}
      </ul>
      <button {{on "click" this.add}} type="button" data-test-add-new>Add New</button>
    </section>
  </template>

  get safeFieldName() {
    if (typeof this.args.fieldName !== 'string') {
      throw new Error(`ContainsManyEditor expects a string fieldName`);
    }
    return this.args.fieldName;
  }

  @action add() {
    // TODO probably each field card should have the ability to say what a new item should be
    let newValue = primitive in this.args.field.card ? null : new this.args.field.card();
    (this.args.model.value as any)[this.safeFieldName].push(newValue);
  }

  @action remove(index: number) {
    (this.args.model.value as any)[this.safeFieldName].splice(index, 1);
  }
}
