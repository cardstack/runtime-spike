import { transformSync } from "@babel/core";
import * as Babel from "@babel/core";
import {
  schemaAnalysisPlugin,
  Options,
  PossibleCardClass,
  ClassReference,
  ExternalReference,
} from "./schema-analysis-plugin";

export type { ClassReference, ExternalReference };

import { parseTemplates } from "@cardstack/ember-template-imports/lib/parse-templates";

//@ts-ignore unsure where these types live
import decoratorsPlugin from "@babel/plugin-syntax-decorators";
//@ts-ignore unsure where these types live
import classPropertiesPlugin from "@babel/plugin-syntax-class-properties";
//@ts-ignore unsure where these types live
import typescriptPlugin from "@babel/plugin-syntax-typescript";

export class ModuleSyntax {
  ast: Babel.types.File;
  possibleCards: PossibleCardClass[];

  constructor(readonly src: string) {
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
    let matches = parseTemplates(this.src, "no-filename", "template");
    for (let match of matches) {
      output.push(this.src.slice(offset, match.start.index));
      output.push("[templte(`"); // use back tick so we can be tolerant of newlines
      output.push(
        this.src
          .slice(match.start.index! + match.start[0].length, match.end.index)
          .replace(/`/g, "\\`")
      );
      output.push("`)]        ");
      offset = match.end.index! + match.end[0].length;
    }
    output.push(this.src.slice(offset));
    return output.join("");
  }
}
