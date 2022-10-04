import type DOMAssertions from 'qunit-dom/dist/assertions';
import {
  waitUntil,
  fillIn as fillInHelper,
  click as clickHelper,
} from '@ember/test-helpers';

// TODO: it would be more efficient to implement a shadowQuerySelector
// that stops at the first found element
export function shadowQuerySelector(
  selector: string | Element,
  root: Document | Element | ShadowRoot | DocumentFragment = document
): Element {
  return shadowQuerySelectorAll(selector, root)[0];
}

export function shadowQuerySelectorAll(
  selector: string | Element,
  root: Document | Element | ShadowRoot | DocumentFragment = document
): Element[] {
  if (typeof selector === 'string') {
    let results = Array.from(root.querySelectorAll(selector));
    for (let checkRoot of Array.from(
      root.querySelectorAll('[data-test-shadow-component]')
    )) {
      results = results.concat(
        shadowQuerySelectorAll(selector, checkRoot.shadowRoot!)
      );
    }
    return results;
  } else if (selector instanceof Element) {
    return [selector];
  } else {
    throw new TypeError('Unexpected Parameter: ' + selector);
  }
}

export async function waitFor(
  selector: string,
  root: Document | Element | ShadowRoot | DocumentFragment = document
): Promise<void> {
  try {
    await waitUntil(() => shadowQuerySelector(selector, root));
  } catch (e) {
    throw new Error(`waitFor timed out waiting for selector "${selector}"`);
  }
}

export async function fillIn(
  selector: string | Element,
  text: string,
  root?: Document | Element | ShadowRoot | DocumentFragment
): Promise<void> {
  try {
    return await fillInHelper(shadowQuerySelector(selector, root), text);
  } catch (e) {
    throw new Error(`fillIn failed for selector "${selector}"`);
  }
}

export async function click(
  selector: string | Element,
  root?: Document | Element | ShadowRoot | DocumentFragment
): Promise<void> {
  try {
    return await clickHelper(shadowQuerySelector(selector, root));
  } catch (e) {
    throw new Error(`click failed for selector "${selector}"`);
  }
}

declare global {
  interface Assert {
    shadowDOM: typeof shadowDOM;
  }
}

function shadowDOM(
  this: Assert,
  target?: string | Element | null | undefined,
  rootElement?: Element | undefined
): DOMAssertions {
  let dom = this.dom(target, rootElement) as any;
  let DOMAssertionsClass = dom.constructor;
  class ShadowDOMAssertions extends DOMAssertionsClass {
    constructor(...args: unknown[]) {
      super(...args);
    }
    findElement() {
      if (this.target === null) {
        return null;
      }
      return shadowQuerySelector(this.target, this.rootElement);
    }
    findElements() {
      if (this.target === null) {
        return null;
      }
      return shadowQuerySelectorAll(this.target, this.rootElement);
    }
  }
  return new ShadowDOMAssertions(
    dom.target,
    dom.rootElement,
    dom.testContext
  ) as unknown as DOMAssertions;
}

QUnit.assert.shadowDOM = shadowDOM;
