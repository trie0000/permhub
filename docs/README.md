# permhub のドキュメント

IT セキュリティ担当者の権限を申請・承認・反映するツール。Power Apps のキャンバスアプリと
SharePoint リストでできている。

## 読む順序

| | 何が書いてあるか |
|---|---|
| [features.md](features.md) | **機能一覧。** 画面ごとに何ができるか |
| [design.md](design.md) | **設計仕様。** 申請の流れ、状態遷移、判定の規則、UI の約束事 |
| [spec-permission.md](spec-permission.md) | 業務上の決めごと（組織区分・権限・申請の定義） |
| [data-model.md](data-model.md) | SharePoint リストの列と、申請明細の JSON |
| [screens.md](screens.md) | 画面ごとのコントロール構成（実装の詳細） |
| [deploy.md](deploy.md) | 別テナントへの導入手順 |
| [cli.md](cli.md) | `deploy.ps1` の仕組みと、Power Platform CLI で踏んだ落とし穴 |
| [powerapps-controls.md](powerapps-controls.md) | モダンコントロールのプロパティ調査 |

## 全体像

```
利用者 ──申請──> PRM_Requests / PRM_RequestItems ──反映──> マスタ 5 本
                        │                                  PRM_Org1
                   管理者が確認                              PRM_Org2
                   ・完了にする（ここで初めてマスタが変わる）  PRM_Users
                   ・差し戻す（何も反映しない）                PRM_UserOrg1
                   ・取り下げる（何も反映しない）              PRM_Grants
```

**申請した時点ではマスタを一切書かない。** 管理者が明細を「完了」にしたときだけ書く。
アプリ側の編集はすべて画面内のコレクションで、申請するまで SharePoint には出ない。

## 開発の回し方

`src/*.pa.yaml` を直して `deploy.ps1` を叩くと、取り込みから公開まで済む。

```powershell
.\setup\deploy.ps1 -SolutionName <ソリューションの一意名>
```

手元の検査（重複プロパティ・存在しないプロパティ・括弧の不一致）は取り込み前に走る。

```bash
python3 setup/check-yaml.py
```
