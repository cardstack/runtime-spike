import type * as Babel from "@babel/core";
import type { types as t } from "@babel/core";
import type { NodePath, Scope } from "@babel/traverse";

interface State {
  opts: Options;
  insideCard: boolean;
}

export interface ExternalReference {
  type: "external";
  module: string;
  name: string;
}

export type ClassReference =
  | ExternalReference
  | {
      type: "internal";
      classIndex: number;
    };

export interface PossibleCardClass {
  super: ClassReference;
  localName: string | undefined;
  exportedAs: string | undefined;
  path: NodePath<t.ClassDeclaration>;
  possibleFields: Map<string, PossibleField>;
}

export interface PossibleField {
  card: ClassReference;
  type: ExternalReference;
  decorator: ExternalReference;
  path: NodePath<t.ClassProperty>;
}

export interface Options {
  possibleCards: PossibleCardClass[];
  reexports: { exportName: string; ref: ExternalReference }[];
  imports: ExternalReference[];
}

export function schemaAnalysisPlugin(_babel: typeof Babel) {
  // let t = babel.types;
  return {
    visitor: {
      ExportNamedDeclaration(
        path: NodePath<t.ExportNamedDeclaration>,
        state: State
      ) {
        // Handle reexports that are not in the module scope
        if (path.node.source != null) {
          for (let specifier of path.node.specifiers) {
            if (specifier.type !== "ExportSpecifier") {
              continue;
            }
            state.opts.reexports.push({
              exportName: getName(specifier.exported),
              ref: {
                type: "external",
                module: path.node.source.value,
                name: specifier.local.name,
              },
            });
          }
        }
      },

      ImportDeclaration(path: NodePath<t.ImportDeclaration>, state: State) {
        // Handle reexports that are in module scope
        for (let specifier of path.node.specifiers) {
          if (specifier.type === "ImportNamespaceSpecifier") {
            continue;
          }
          state.opts.imports.push({
            type: "external",
            module: path.node.source.value,
            name:
              specifier.type === "ImportDefaultSpecifier"
                ? "default"
                : getName(specifier.imported),
          });
          let binding = specifier.local
            ? path.scope.getBinding(getName(specifier.local))
            : undefined;
          if (!binding) {
            continue;
          }
          let exportSpecifierLocal = binding.referencePaths.find((b) =>
            b.parentPath?.isExportSpecifier()
          ) as NodePath<t.Identifier> | undefined;
          if (exportSpecifierLocal) {
            let exportName = getName(
              (exportSpecifierLocal.parentPath as NodePath<t.ExportSpecifier>)
                .node.exported
            );
            state.opts.reexports.push({
              exportName,
              ref: {
                type: "external",
                module: path.node.source.value,
                name:
                  specifier.type === "ImportDefaultSpecifier"
                    ? "default"
                    : getName(specifier.imported),
              },
            });
          }
        }
      },

      ClassDeclaration: {
        enter(path: NodePath<t.ClassDeclaration>, state: State) {
          if (!path.node.superClass) {
            return;
          }

          let sc = path.get("superClass");
          if (sc.isReferencedIdentifier()) {
            let classRef = makeClassReference(path.scope, sc.node.name, state);
            if (classRef) {
              state.insideCard = true;
              let exportedAs: string | undefined;
              let { parentPath } = path;
              let localName = path.node.id ? path.node.id.name : undefined;
              if (parentPath.isExportNamedDeclaration()) {
                // the class declaration is part of a named export
                exportedAs = localName;
              } else if (parentPath.isExportDefaultDeclaration()) {
                // the class declaration is part of a default export
                exportedAs = "default";
              } else {
                // the class's identifier is referenced in a node whose parent is an ExportSpecifier
                let binding = localName
                  ? path.scope.getBinding(localName)
                  : undefined;
                if (binding) {
                  let maybeExportSpecifierLocal = binding.referencePaths.find(
                    (b) => b.parentPath?.isExportSpecifier()
                  ) as NodePath<t.Identifier> | undefined;
                  if (maybeExportSpecifierLocal) {
                    exportedAs = getName(
                      (
                        maybeExportSpecifierLocal.parentPath as NodePath<t.ExportSpecifier>
                      ).node.exported
                    );
                  }
                }
              }

              state.opts.possibleCards.push({
                super: classRef,
                localName,
                path,
                possibleFields: new Map(),
                exportedAs,
              });
            }
          }
        },

        exit(_path: NodePath<t.ClassDeclaration>, state: State) {
          state.insideCard = false;
        },
      },

      Decorator(path: NodePath<t.Decorator>, state: State) {
        if (!state.insideCard) {
          return;
        }

        let expression = path.get("expression");
        if (!expression.isIdentifier()) {
          return;
        }
        let decoratorInfo = getNamedImportInfo(
          path.scope,
          expression.node.name
        );
        if (!decoratorInfo) {
          return; // our @field decorator must originate from a named import
        }

        let maybeClassProperty = path.parentPath;
        if (
          !maybeClassProperty.isClassProperty() ||
          maybeClassProperty.node.key.type !== "Identifier"
        ) {
          return;
        }

        let maybeCallExpression = maybeClassProperty.node.value;
        if (
          maybeCallExpression?.type !== "CallExpression" ||
          maybeCallExpression.arguments.length === 0
        ) {
          return; // our field type function (e.g. contains()) must have at least one argument (the field card)
        }

        let maybeFieldTypeFunction = maybeCallExpression.callee;
        if (maybeFieldTypeFunction.type !== "Identifier") {
          return;
        }

        let fieldTypeInfo = getNamedImportInfo(
          path.scope,
          maybeFieldTypeFunction.name
        );
        if (!fieldTypeInfo) {
          return; // our field type function (e.g. contains()) must originate from a named import
        }

        let [maybeFieldCard] = maybeCallExpression.arguments; // note that the 2nd argument is the computeVia
        if (maybeFieldCard.type !== "Identifier") {
          return;
        }

        let fieldCard = makeClassReference(
          path.scope,
          maybeFieldCard.name,
          state
        );
        if (!fieldCard) {
          return; // the first argument to our field type function must be a card reference
        }

        let possibleField: PossibleField = {
          card: fieldCard,
          path: maybeClassProperty,
          type: {
            type: "external",
            module: getName(fieldTypeInfo.declaration.node.source),
            name: getName(fieldTypeInfo.specifier.node.imported),
          },
          decorator: {
            type: "external",
            module: getName(decoratorInfo.declaration.node.source),
            name: getName(decoratorInfo.specifier.node.imported),
          },
        };
        // the card that contains this field will always be the last card that
        // was added to possibleCards
        let [card] = state.opts.possibleCards.slice(-1);
        let fieldName = maybeClassProperty.node.key.name;
        card.possibleFields.set(fieldName, possibleField);
      },
    },
  };
}

export function error(path: NodePath<any>, message: string) {
  return path.buildCodeFrameError(message, CompilerError);
}
class CompilerError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "CompilerError";
    if (typeof Error.captureStackTrace === "function") {
      Error.captureStackTrace(this, this.constructor);
    } else if (!this.stack) {
      this.stack = new Error(message).stack;
    }
  }
}

function makeClassReference(
  scope: Scope,
  name: string,
  state: State
): ClassReference | undefined {
  let binding = scope.getBinding(name);
  if (
    binding?.path.isImportSpecifier() ||
    binding?.path.isImportDefaultSpecifier()
  ) {
    let parent = binding.path.parentPath as NodePath<t.ImportDeclaration>;
    return {
      type: "external",
      module: parent.node.source.value,
      name: binding.path.isImportDefaultSpecifier()
        ? "default"
        : getName(binding.path.node.imported),
    };
  }

  if (binding?.path.isClassDeclaration()) {
    let superClassNode = binding.path.node;
    let superClassIndex = state.opts.possibleCards.findIndex(
      (card) => card.path.node === superClassNode
    );
    if (superClassIndex >= 0) {
      return {
        type: "internal",
        classIndex: superClassIndex,
      };
    }
  }

  return undefined;
}

function getNamedImportInfo(
  scope: Scope,
  name: string
):
  | {
      declaration: NodePath<t.ImportDeclaration>;
      specifier: NodePath<t.ImportSpecifier>;
    }
  | undefined {
  let binding = scope.getBinding(name);
  if (!binding?.path.isImportSpecifier()) {
    return undefined;
  }

  return {
    declaration: binding.path.parentPath as NodePath<t.ImportDeclaration>,
    specifier: binding.path,
  };
}

function getName(node: t.Identifier | t.StringLiteral) {
  if (node.type === "Identifier") {
    return node.name;
  } else {
    return node.value;
  }
}
