import { QUERY_CATALOG } from "./environment.ts";
export function commandDomain(name: string): string {
  if (name.startsWith("public_")) return "public";
  if (name.includes("short_term_goal")) return "goals";
  if (
    [
      "resolve_relationship_dialogue",
      "propose_relationship",
      "respond_relationship",
      "end_relationship",
      "express_support",
    ].includes(name)
  )
    return "actors";
  if (["move", "travel"].includes(name)) return "map";
  if (["till", "plant", "harvest"].includes(name)) return "farm";
  if (["buy", "sell", "request_supply"].includes(name)) return "market";
  if (["build", "rent_production", "manage_building"].includes(name))
    return "buildings";
  if (
    [
      "survey",
      "collect_sample",
      "register_discovery",
      "prepare_supplies",
    ].includes(name) ||
    /intelligence|investigation/.test(name)
  )
    return "knowledge";
  if (name === "start_leisure") return "self";
  if (/activity/.test(name)) return "social";
  if (/route_repair/.test(name)) return "environment";
  if (
    /trade|cooperation|contribution|role_change/.test(name) ||
    name === "send_message"
  )
    return "actors";
  return "tasks";
}
const schema = (
  name: string,
  description: string,
  properties: Record<string, unknown>,
  required: string[] = [],
) => ({
  type: "function",
  function: {
    name,
    description,
    parameters: {
      type: "object",
      properties,
      required,
      additionalProperties: false,
    },
  },
});
const str = { type: "string", maxLength: 500 };
export function readDefinition(
  name: string,
  domains: string[],
  actionNames: readonly string[] = [],
): Record<string, unknown> {
  if (name === "discover_tools")
    return schema(
      name,
      '发现所需领域的查询入口和行动目录，不执行行动、不读取世界实例。首次只填 domains，例如 {"domains":["farm"]}。查询事实使用 query_world；行动名称只能从返回的 available_actions 选择，不能填写意图描述或读取工具名。',
      {
        domains: {
          type: "array",
          items: { type: "string", enum: domains },
          minItems: 1,
          maxItems: 3,
        },
        ...(actionNames.length
          ? {
              actions: {
                type: "array",
                description:
                  "可选：从已发现的 available_actions 中选取精确行动名，替换当前额外行动菜单；省略则保留已启用行动。不是要查询的信息或要立即执行的动作。",
                items: { type: "string", enum: actionNames },
                maxItems: 6,
                uniqueItems: true,
              },
            }
          : {}),
      },
      ["domains"],
    );
  if (name === "query_map")
    return schema(
      name,
      "按地点名称、别名或ID查询实时导航坐标。例：{query:南湖}；返回可达岸边/入口与可直接调用的move参数。查询不等于移动。",
      {
        query: str,
        id: str,
        cursor: { type: "integer", minimum: 0 },
        limit: { type: "integer", minimum: 1, maximum: 10 },
      },
    );
  if (name === "query_world")
    return schema(
      name,
      "查询授权事实，无需先读overview。按discover_tools返回的query_catalog选择分区。省略section时id/ids自动查detail、query自动搜索，否则overview。多词query匹配任一词；精确批量详情用ids。租生产先查buildings/quote。",
      {
        domain: { type: "string", enum: domains },
        section: {
          type: "string",
          enum: [
            "overview",
            ...new Set(
              domains.flatMap((d) => QUERY_CATALOG[d]?.sections ?? []),
            ),
          ],
        },
        id: str,
        ids: {
          type: "array",
          items: str,
          minItems: 1,
          maxItems: 10,
          uniqueItems: true,
        },
        query: str,
        recipe_id: str,
        batches: { type: "integer", minimum: 1, maximum: 100 },
        cursor: { type: "integer", minimum: 0 },
        limit: { type: "integer", minimum: 1, maximum: 10 },
      },
      ["domain"],
    );
  if (name === "recall_memory")
    return schema(
      name,
      "检索自己在本存档中的重要记忆。历史事实不是实时状态。",
      { query: str },
      ["query"],
    );
  if (name === "inspect_event")
    return schema(name, "按来源ID查询自己的完整经历原文。", { event_id: str }, [
      "event_id",
    ]);
  if (name === "inspect_history_segment")
    return schema(name, "分页查询自己的早期事件原文。", {
      cursor: { type: "integer", minimum: 0 },
    });
  return schema(name, "重新核对自己的完整资源。", {});
}
export function validLoopRead(
  name: string,
  args: Record<string, unknown>,
  domains: string[],
): boolean {
  if (name === "discover_tools")
    return (
      Object.keys(args).every((k) => ["domains", "actions"].includes(k)) &&
      (args.actions === undefined ||
        (Array.isArray(args.actions) &&
          args.actions.length <= 6 &&
          args.actions.every((x) => typeof x === "string"))) &&
      Array.isArray(args.domains) &&
      args.domains.length > 0 &&
      args.domains.length <= 3 &&
      args.domains.every((x) => domains.includes(String(x)))
    );
  if (name === "query_map")
    return (
      domains.includes("map") &&
      Object.keys(args).every((k) =>
        ["query", "id", "cursor", "limit"].includes(k),
      ) &&
      validLoopRead(
        "query_world",
        { ...args, domain: "map", section: "regions" },
        domains,
      )
    );
  if (name === "query_world")
    return (
      domains.includes(String(args.domain)) &&
      Object.keys(args).every((k) =>
        [
          "domain",
          "section",
          "id",
          "ids",
          "query",
          "recipe_id",
          "batches",
          "cursor",
          "limit",
        ].includes(k),
      ) &&
      ["section", "id", "query", "recipe_id"].every(
        (k) =>
          args[k] === undefined ||
          (typeof args[k] === "string" && String(args[k]).length <= 500),
      ) &&
      (args.ids === undefined ||
        (Array.isArray(args.ids) &&
          args.ids.length > 0 &&
          args.ids.length <= 10 &&
          new Set(args.ids).size === args.ids.length &&
          args.ids.every(
            (x) => typeof x === "string" && x.length > 0 && x.length <= 500,
          ))) &&
      (args.batches === undefined ||
        (Number.isSafeInteger(args.batches) &&
          Number(args.batches) >= 1 &&
          Number(args.batches) <= 100)) &&
      (args.cursor === undefined ||
        (Number.isSafeInteger(args.cursor) && Number(args.cursor) >= 0)) &&
      (args.limit === undefined ||
        (Number.isSafeInteger(args.limit) &&
          Number(args.limit) >= 1 &&
          Number(args.limit) <= 10))
    );
  if (name === "recall_memory" || name === "inspect_event") {
    const key = name === "recall_memory" ? "query" : "event_id";
    return (
      Object.keys(args).length === 1 &&
      typeof args[key] === "string" &&
      String(args[key]).length <= 500
    );
  }
  if (name === "inspect_history_segment")
    return (
      Object.keys(args).every((k) => k === "cursor") &&
      (args.cursor === undefined ||
        (Number.isSafeInteger(args.cursor) && Number(args.cursor) >= 0))
    );
  return name === "inspect_self_resources" && Object.keys(args).length === 0;
}
