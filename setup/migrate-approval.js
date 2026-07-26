/*
 * 移行スクリプト: 承認・作業管理（申請の統合と明細ごとの状態）
 *
 * create-lists.js で作った 7 リストに対して、後から次を足す。
 * 既に流したサイトでも安全に再実行できる（列があれば飛ばす）。
 *
 *   PRM_Requests.Status    選択肢に INPROGRESS / PARTIAL を追加
 *   PRM_Requests.ReqType   選択肢に MIXED を追加（1 申請に複数種別が混ざるため）
 *   PRM_RequestItems       ItemStatus / ItemNote / HandledAt / HandledBy を追加
 *                          （ItemStatus の選択肢に CANCELED = 取り下げ を含む）
 *   PRM_Config             新規（設定値を 1 行 1 キーで持つ）
 *
 * 使い方:
 *   1. 対象の SharePoint サイトをブラウザで開く（サイト所有者権限が必要）
 *   2. DevTools のコンソールを開く
 *   3. 下の SITE_URL を対象サイトに書き換える
 *   4. 全文を貼り付けて実行
 *
 * 実行後、PRM_Config の AdminGroupId に
 * 「管理者にしたい Teams（Microsoft 365 グループ）の ID」を入れる。
 * ID はそのチームの SharePoint サイトで
 *   /_api/site?$select=GroupId
 * を開けば分かる。**ID はアプリのコードには書かない**（このリストで持つ）。
 */

const SITE_URL = "https://YOUR-TENANT.sharepoint.com/sites/YOUR-SITE";

(async () => {
  const web = SITE_URL.replace(/\/+$/, "");
  const ctx = await (await fetch(web + "/_api/contextinfo", {
    method: "POST", headers: { Accept: "application/json;odata=verbose" },
    credentials: "same-origin",
  })).json();
  const H = {
    Accept: "application/json;odata=verbose",
    "Content-Type": "application/json;odata=verbose",
    "X-RequestDigest": ctx.d.GetContextWebInformation.FormDigestValue,
  };
  const log = (m) => console.log("[PRM] " + m);
  const get = async (u) =>
    (await (await fetch(web + u, {
      headers: { Accept: "application/json;odata=nometadata" }, credentials: "same-origin",
    })).json());
  const post = async (u, body, extra) => {
    const r = await fetch(web + u, {
      method: "POST", credentials: "same-origin",
      headers: { ...H, ...(extra || {}) }, body: JSON.stringify(body),
    });
    if (!r.ok) throw new Error(u + " → " + r.status + " " + (await r.text()).slice(0, 300));
    return r;
  };
  const merge = (u, body) => post(u, body, { "X-HTTP-Method": "MERGE", "IF-MATCH": "*" });
  const fieldsOf = async (list) =>
    (await get(`/_api/web/lists/getbytitle('${list}')/fields?$select=InternalName&$top=500`))
      .value.map((f) => f.InternalName);

  // ---- 1. 選択肢の追加 ----------------------------------------------------
  // 選択肢列は Choices を丸ごと入れ替える（既存の値は消さない）
  const addChoices = async (list, internal, add) => {
    const f = await get(
      `/_api/web/lists/getbytitle('${list}')/fields/getByInternalNameOrTitle('${internal}')` +
      "?$select=Choices,TypeAsString");
    const now = f.Choices || [];
    const next = now.concat(add.filter((c) => !now.includes(c)));
    if (next.length === now.length) { log(`${list}.${internal} 選択肢は既に最新`); return; }
    await merge(
      `/_api/web/lists/getbytitle('${list}')/fields/getByInternalNameOrTitle('${internal}')`,
      { __metadata: { type: "SP.FieldChoice" }, Choices: { results: next } });
    log(`${list}.${internal} に ${add.join(",")} を追加`);
  };

  // SUBMITTED  申請済み（手が付いていない）
  // INPROGRESS 確認中（管理者が受理した明細がある）
  // PARTIAL    一部完了（完了と差し戻しが混ざった）
  // APPLIED    完了（全明細が完了）
  // REJECTED   差し戻し（全明細が差し戻し）
  await addChoices("PRM_Requests", "Status", ["INPROGRESS", "PARTIAL"]);
  await addChoices("PRM_Requests", "ReqType", ["MIXED"]);
  // 既に ItemStatus がある環境向け（列の作り直しはせず選択肢だけ足す）
  const hasItemStatus = (await fieldsOf("PRM_RequestItems")).includes("ItemStatus");
  if (hasItemStatus) await addChoices("PRM_RequestItems", "ItemStatus", ["CANCELED"]);

  // ---- 2. PRM_RequestItems の列追加 --------------------------------------
  const OPT = 25;
  const T = (n, d, len) => `<Field Type="Text" DisplayName="${d}" Name="${n}" StaticName="${n}" MaxLength="${len || 255}" />`;
  const C = (n, d, ch, def) => `<Field Type="Choice" DisplayName="${d}" Name="${n}" StaticName="${n}" Format="Dropdown"><CHOICES>${ch.map((c) => `<CHOICE>${c}</CHOICE>`).join("")}</CHOICES>${def ? `<Default>${def}</Default>` : ""}</Field>`;
  const NO = (n, d) => `<Field Type="Note" DisplayName="${d}" Name="${n}" StaticName="${n}" NumLines="4" RichText="FALSE" AppendOnly="FALSE" />`;
  const DT = (n, d) => `<Field Type="DateTime" DisplayName="${d}" Name="${n}" StaticName="${n}" Format="DateTime" />`;

  const addFields = async (list, defs) => {
    const have = await fieldsOf(list);
    for (const [name, xml] of defs) {
      if (have.includes(name)) { log(`${list}.${name} は既にある`); continue; }
      await post(`/_api/web/lists/getbytitle('${list}')/fields/createfieldasxml`, {
        parameters: {
          __metadata: { type: "SP.XmlSchemaFieldCreationInformation" },
          SchemaXml: xml, Options: OPT,
        },
      });
      log(`${list}.${name} を追加`);
    }
  };

  // 明細の状態。操作は申請まるごとなので、全明細に同じ値が入る
  //   PENDING  未対応
  //   READY    確認中（内容 OK、作業前）
  //   DONE     完了（この時点でマスタに反映される）
  //   REJECTED 差し戻し（何も反映しない）
  //   CANCELED 取り下げ（申請者が引っ込めた）
  await addFields("PRM_RequestItems", [
    ["ItemStatus", C("ItemStatus", "明細の状態", ["PENDING", "READY", "DONE", "REJECTED", "CANCELED"], "PENDING")],
    ["ItemNote", NO("ItemNote", "差し戻し理由・作業メモ")],
    ["HandledAt", DT("HandledAt", "状態変更日時")],
    ["HandledBy", T("HandledBy", "状態変更者", 100)],
  ]);

  // 明細は「表示・操作の単位」で束ねる。行そのものは対象 1 件ずつのまま
  // （反映処理を単純に保つため）で、Seq が同じ行が 1 明細として扱われる。
  //   GroupKind ORG1 / ORG2 / USER
  //   GroupKey  表示する対象（組織区分1 コード／組織区分2 コードを ";" で並べたもの／グローバルID）
  await addFields("PRM_RequestItems", [
    ["GroupKind", T("GroupKind", "明細の種類", 20)],
    ["GroupKey", T("GroupKey", "明細の対象", 255)],
  ]);

  // 差し戻し・取り下げの理由は**申請まるごと**に付く。明細ごとには持たない
  // （明細は「組織区分1 の変更」「組織区分2 の変更」「利用者ごとの変更」の単位で、
  //   1 明細に複数の対象がまとまるため、理由を明細に紐づける意味がない）
  await addFields("PRM_Requests", [
    ["DecisionNote", NO("DecisionNote", "差し戻し・取り下げの理由")],
  ]);

  // ---- 3. 索引 ------------------------------------------------------------
  const idx = { PRM_Requests: ["Status"], PRM_RequestItems: ["ItemStatus"] };
  for (const [l, cols] of Object.entries(idx))
    for (const c of cols)
      await merge(
        `/_api/web/lists/getbytitle('${l}')/fields/getByInternalNameOrTitle('${c}')`,
        { __metadata: { type: "SP.Field" }, Indexed: true });
  log("索引を設定");

  // ---- 4. PRM_Config -----------------------------------------------------
  // 1 行 1 キー。テナント固有の値（グループ ID 等）はここに入れ、コードには書かない
  const lists = (await get("/_api/web/lists?$select=Title&$top=500")).value.map((l) => l.Title);
  if (!lists.includes("PRM_Config")) {
    await post("/_api/web/lists", {
      __metadata: { type: "SP.List" }, Title: "PRM_Config", BaseTemplate: 100,
      Description: "権限申請: 設定 (1 行 = 1 キー)",
      AllowContentTypes: false, ContentTypesEnabled: false,
    });
    await merge("/_api/web/lists/getbytitle('PRM_Config')/fields/getByInternalNameOrTitle('Title')",
      { __metadata: { type: "SP.Field" }, Title: "設定キー" });
    await addFields("PRM_Config", [
      ["Value", T("Value", "値")],
      ["Descr", T("Descr", "説明")],
    ]);
    await merge("/_api/web/lists/getbytitle('PRM_Config')/fields/getByInternalNameOrTitle('Title')",
      { __metadata: { type: "SP.Field" }, Indexed: true });
    await merge("/_api/web/lists/getbytitle('PRM_Config')/fields/getByInternalNameOrTitle('Title')",
      { __metadata: { type: "SP.Field" }, EnforceUniqueValues: true });
    log("PRM_Config 作成");
  } else {
    log("PRM_Config は既にある");
    await addFields("PRM_Config", [
      ["Value", T("Value", "値")],
      ["Descr", T("Descr", "説明")],
    ]);
  }

  const cfgType = (await get(
    "/_api/web/lists/getbytitle('PRM_Config')?$select=ListItemEntityTypeFullName"
  )).ListItemEntityTypeFullName;
  const cfgHave = (await get(
    "/_api/web/lists/getbytitle('PRM_Config')/items?$select=Title&$top=500"
  )).value.map((i) => i.Title);
  const seed = [
    ["AdminGroupId", "", "管理者の Teams(Microsoft 365 グループ) の ID。ここが空なら申請履歴に管理者向けの操作が出ない"],
  ];
  for (const [k, v, d] of seed) {
    if (cfgHave.includes(k)) { log(`PRM_Config.${k} は既にある`); continue; }
    await post("/_api/web/lists/getbytitle('PRM_Config')/items",
      { __metadata: { type: cfgType }, Title: k, Value: v, Descr: d });
    log(`PRM_Config.${k} を投入`);
  }

  // ---- 5. 既存明細の状態を埋める ------------------------------------------
  // これまでの申請は「申請した時点でマスタに反映」だったので、すべて完了扱いにする
  const items = (await get(
    "/_api/web/lists/getbytitle('PRM_RequestItems')/items" +
    "?$select=Id,ItemStatus&$top=5000"
  )).value.filter((i) => !i.ItemStatus);
  const itemType = (await get(
    "/_api/web/lists/getbytitle('PRM_RequestItems')?$select=ListItemEntityTypeFullName"
  )).ListItemEntityTypeFullName;
  for (const it of items)
    await merge(`/_api/web/lists/getbytitle('PRM_RequestItems')/items(${it.Id})`,
      { __metadata: { type: itemType }, ItemStatus: "DONE" });
  log(`既存明細 ${items.length} 件を DONE にした`);

  // ---- 6. 既存の差し戻し理由を申請側へ移す --------------------------------
  // 理由は明細ごとに持っていた。申請 1 本につき理由は 1 つなので、
  // 最初に見つかった ItemNote を DecisionNote に写す（明細側は消さずに残す）
  const reqType = (await get(
    "/_api/web/lists/getbytitle('PRM_Requests')?$select=ListItemEntityTypeFullName"
  )).ListItemEntityTypeFullName;
  const noted = (await get(
    "/_api/web/lists/getbytitle('PRM_RequestItems')/items" +
    "?$select=ReqNo,ItemNote&$top=5000"
  )).value.filter((i) => i.ItemNote);
  const byReq = {};
  for (const i of noted) if (!byReq[i.ReqNo]) byReq[i.ReqNo] = i.ItemNote;
  let moved = 0;
  for (const [no, note] of Object.entries(byReq)) {
    const r = (await get(
      "/_api/web/lists/getbytitle('PRM_Requests')/items" +
      `?$select=Id,DecisionNote&$filter=Title eq '${no}'`)).value[0];
    if (!r || r.DecisionNote) continue;
    await merge(`/_api/web/lists/getbytitle('PRM_Requests')/items(${r.Id})`,
      { __metadata: { type: reqType }, DecisionNote: note });
    moved++;
  }
  log(`差し戻し理由 ${moved} 件を申請側へ移した`);

  log("完了。PRM_Config の AdminGroupId にグループ ID を入れる。");
})().catch((e) => console.error("[PRM] 失敗:", e));
