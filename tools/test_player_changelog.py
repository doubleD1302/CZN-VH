import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import player_changelog as player
import android_sync as sync
import change_history as history


class PlayerChangelogTests(unittest.TestCase):
    def change(self, identity='card@desc@c_1003_test', kind='edited', domain='text', before='Cũ', after='Mới'):
        return {'id': identity, 'domain': domain, 'kind': kind, 'group': 'Internal Phase 9 English Category',
                'before': before, 'after': after}

    def delta(self, *changes):
        return {'baseline_version': '1.5.3', 'changes': list(changes)}

    def context(self):
        return player.Context({'card@name@c_1003_test': '名前', 'card@desc@c_1003_test': '説明'},
                              {'card@name@c_1003_test': 'Heart Breaker'},
                              {'card@name@c_1003_test': 'Tên cũ không được dùng'}, {'1003': 'Rei'})

    def test_official_card_name_exact_id_but_owner_not_inferred_from_digits(self):
        model=player.model(self.delta(self.change()),self.context())
        info=model['changes'][0]['player_context']
        self.assertEqual(info['entity'],'Thẻ Heart Breaker')
        self.assertEqual(info['owner_status'],'not_established')
        self.assertNotIn('Rei',model['text']);self.assertNotIn('Internal Phase',model['text'])
        self.assertIn('sửa bản dịch',model['text'])

    def test_explicit_owner_reference_can_name_character(self):
        c=self.context();c.table('db/card(real)@card.db',[{'id':'c_1003_test','name':'card@name@c_1003_test',
             'desc':'card@desc@c_1003_test','owner_link_char_base_id':'1003'}])
        info=player.model(self.delta(self.change()),c)['changes'][0]['player_context']
        self.assertEqual(info['entity'],'Rei · Thẻ Heart Breaker')
        self.assertEqual(info['status'],'explicit_owner_reference')

    def test_skill_names_use_approved_classification_not_whole_prefix(self):
        name='account_skill@name@account_skill_1';desc='account_skill@desc@account_skill_1'
        c=player.Context({name:'名前',desc:'説明'},{name:'Undo the Last Action'},{name:'Tên VI cũ'},
                          name_kinds={name:'skill_name'})
        c.table('db/account_skill@account_skill.db',[{'id':'account_skill_1','name':name,'desc':desc}])
        row=player.model(self.delta(self.change(desc)),c)['changes'][0]
        self.assertEqual(row['player_context']['entity'],'Kỹ năng Undo the Last Action')
        self.assertEqual(row['player_context']['section'],player.SECTIONS[3])
        pending=player.Context(c.ja,c.en,c.values)
        pending.table('db/account_skill@account_skill.db',[{'id':'account_skill_1','name':name,'desc':desc}])
        info=player.model(self.delta(self.change(desc)),pending)['changes'][0]['player_context']
        self.assertEqual(info['status'],'classification_pending')
        self.assertNotIn('Kỹ năng',info['entity'])
        self.assertIn('Tên VI cũ',info['entity'])

    def test_skill_registry_rejects_pending_or_changed_source(self):
        from types import SimpleNamespace
        key='account_skill@name@account_skill_1';source=b'fixture manifest'
        row={'id':key,'name_kind':'skill_name','display_policy':'official_en_only','source_ja':'名前',
             'reference_en':'Undo','official_en_name':'Undo','review_status':'reviewed','reviewer':'reviewer',
             'classification_evidence':'same-ID source review'}
        with tempfile.TemporaryDirectory() as temp:
            home=Path(temp);archive=SimpleNamespace(data=source,files=[])
            for status,english,expected in [('reviewed','Undo',{key:'skill_name'}),
                    ('candidate','Undo',{}),('pending_source_review','Undo',{}),('reviewed','Changed',{})]:
                row.update(review_status=status,reference_en=english)
                (home/'PHAN_LOAI_TEN.json').write_text(json.dumps({'source_manifest_sha256':player.digest(source),'entries':[row]}))
                ctx=player.from_archive(archive,{key:'名前'},{key:'Undo'},home,self.delta(),{'values':{'text':{}}})
                self.assertEqual(ctx.name_kinds,expected)

    def test_conflicting_owners_are_ambiguous_not_guessed(self):
        c=self.context();c.names['1040']='Lucas'
        for owner in ['1003','1040']:
            c.table('db/card(real)@card.db',[{'id':'c_1003_test','desc':'card@desc@c_1003_test',
                 'name':'card@name@c_1003_test','owner_link_char_base_id':owner}])
        self.assertEqual(player.model(self.delta(self.change()),c)['changes'][0]['player_context']['status'],'ambiguous')

    def test_owned_reference_does_not_hide_shared_unowned_reference(self):
        c=self.context();c.ja['card@name@other']='別名';c.en['card@name@other']='Other Card'
        c.table('db/card(real)@card.db',[{'id':'owner_card','name':'card@name@c_1003_test',
          'desc':'card@desc@c_1003_test','owner_link_char_base_id':'1003'},
          {'id':'other_card','name':'card@name@other','desc':'card@desc@c_1003_test'}])
        info=player.model(self.delta(self.change()),c)['changes'][0]['player_context']
        self.assertEqual(info['status'],'ambiguous')

    def test_character_names_require_verified_same_en_and_jp(self):
        from types import SimpleNamespace
        with tempfile.TemporaryDirectory() as temp:
            home=Path(temp);source=b'fixture manifest'
            row={'id':'char_base@name@1003','kind':'character_name','source_ja':'名前',
                 'reference_en':'Rei','locked_name':'Rei','review_status':'source_verified'}
            archive=SimpleNamespace(data=source,files=[])
            for status,english,expected in [('source_verified','Rei',{'1003':'Rei'}),
                 ('candidate','Rei',{}),('pending_source_review','Rei',{}),('source_verified','Wrong',{})]:
                row.update(review_status=status,reference_en=english)
                (home/'TEN_NHAN_VAT.json').write_text(json.dumps({'source_manifest_sha256':player.digest(source),'entries':[row]}))
                ctx=player.from_archive(archive,{'char_base@name@1003':'名前'},
                      {'char_base@name@1003':'Rei'},home,self.delta(),{'values':{'text':{}}})
                self.assertEqual(ctx.names,expected)

    def test_monster_card_never_assigned_to_character_by_number(self):
        info=player.model(self.delta(self.change('card@desc@mon_1003')),self.context())['changes'][0]['player_context']
        self.assertEqual(info['owner_status'],'not_established');self.assertNotIn('Rei',info['entity'])

    def test_map_name_from_source_metadata_not_category(self):
        key='story_map_chapter@desc@m0101';name='story_map_chapter@name@m0101'
        c=player.Context({key:'説明',name:'黒い薔薇'},{name:'Black Rose'},{name:'Hoa hồng đen'})
        c.table('db/story_map@story_map_chapter.db',[{'id':'chapter01','type':'main_story','number':'1','name':name,'desc':key}])
        model=player.model(self.delta(self.change(key,kind='new')),c)
        self.assertIn('Chương 1 · Hoa hồng đen',model['text']);self.assertIn('thêm tiếng Việt 1 dòng',model['text'])
        self.assertNotIn('toàn bộ Chương 1',model['text'])

    def test_cross_table_row_collision_cannot_establish_map(self):
        name='story_map_chapter@name@ch1';key='i_test@line'
        c=player.Context({name:'名前',key:'文'},{name:'Black Rose'})
        c.table('db/story_map@story_map_chapter.db',[{'id':'chapter1','name':name,'link_story_map_node_key':'shared'}])
        c.table('db/story_map@story_map_node.db',[{'id':'shared'}])
        c.table('db/card@card.db',[{'id':'shared'}])
        c.script('enact/shared.sract',[{'yuna':key}],{key})
        info=player.model(self.delta(self.change(key)),c)['changes'][0]['player_context']
        self.assertEqual(info['status'],'unresolved')

    def test_prepare_freezes_exact_payload_details_and_private_hash(self):
        from types import SimpleNamespace
        from installer_core import write_json
        with tempfile.TemporaryDirectory() as temp:
            home=Path(temp);data=home/'data';data.mkdir();build=home/'build';(build/'chunks').mkdir(parents=True)
            key=home/'fixture.pk8';key.write_bytes(b'not-a-key')
            ident='card@desc@c_1003_test'
            rows=[{'id':ident,'source_ja':'説明','text_vi':'Mới'},
                  {'id':'rejected','source_ja':'旧い','text_vi':'Sai nguồn'}]
            write_json(data/'translations.json',{'entries':rows})
            previous={'patch_code':10503,'patch_version':'1.5.3','patch_sha256':'fixture','app_code':10502}
            history.acknowledge(home,{'values':{'text':{ident:'Cũ'},'story':{}}},previous,
                                {'public_verified':True,'bundle_sha256':'fixture'})
            snapshot={'values':{'text':{ident:'Mới','rejected':'新しい'},'story':{}},'eligible':{'text':[ident],'story':[]}}
            original=SimpleNamespace(root=home,overrides={})
            inst=SimpleNamespace(home=home,data=data,build=lambda:(original,build,{}))
            def bundle(orig,target,out,version,code,sign):
                out.mkdir(parents=True);f=out/f'CZN_Android_v{version}.cznpatch';f.write_bytes(b'fixture')
                (out/'TRANSLATION_SNAPSHOT.json').write_text(json.dumps(snapshot),encoding='utf-8')
                return f,{'bundle_bytes':7,'bundle_sha256':sync.digest(f)}
            def app_build(home,out,version,code,bundle,log):
                apk=out/f'CZN_VietHoa_Android_v{version}.apk';apk.write_bytes(b'new-apk')
                evidence={'version':version,'code':code,'full_app_update':True,'apk_sha256':sync.digest(apk)}
                (out/'APP_BUILD_EVIDENCE.json').write_text(json.dumps(evidence))
                return apk,evidence
            with patch.object(sync,'check_updates',return_value=previous),patch.object(sync,'validate_new_version',return_value=('1.5.5',10505)), \
                 patch.object(history,'ensure_baseline'),patch('czn_format.Archive'),patch('package_android_patch.make_bundle',side_effect=bundle), \
                 patch.object(sync,'sign_metadata',side_effect=lambda raw,k:Path(raw).read_bytes()), \
                 patch.object(sync,'verify_metadata',side_effect=json.loads),patch('app_package.build_app',side_effect=app_build) as app_builder,patch.object(player,'for_home',return_value=self.context()) as context:
                record=sync.prepare(inst,'1.5.5','','',''+str(key),log=lambda _:None)
            details=sync.load_player_details(record)
            self.assertEqual([row['id'] for row in details['changes']],[ident])
            self.assertEqual(details['text'],record['automatic_notice'])
            self.assertEqual(record['notice']['body'],details['text'])
            self.assertEqual(context.call_args.args[2],snapshot)
            self.assertEqual(record['app']['app_code'],10505)
            self.assertIn('CZN_VietHoa_Android_v1.5.5.apk',record['asset_hashes'])
            self.assertEqual(app_builder.call_args.args[4].name,'CZN_Android_v1.5.5.cznpatch')
            self.assertNotIn('PLAYER_CHANGELOG.json',record['asset_hashes'])
            self.assertIn('Thẻ Heart Breaker',details['text'])
            self.assertEqual(details['changes'][0]['before'],'Cũ')
            self.assertEqual(details['changes'][0]['after'],'Mới')

    def test_missing_map_metadata_remains_unknown(self):
        model=player.model(self.delta(self.change('i_403s01@s1')),player.Context())
        self.assertIn('chưa xác định bản đồ',model['text']);self.assertNotIn('Diallos',model['text'])

    def test_unrecognized_story_scene_not_claimed_as_tutorial(self):
        change=self.change('side_story_foo',domain='story');change['metadata']={'scene':'side_story_foo'}
        model=player.model(self.delta(change))
        self.assertNotIn('Hướng dẫn',model['text']);self.assertIn('chưa xác định chương',model['text'])
        self.assertEqual(history.group_name('story',{'id':'side_story_foo','scene':'side_story_foo'}),'Cốt truyện · Chưa xác định chương')

    def test_trial_character_and_named_cards_from_same_object_description(self):
        key='combatant_trial@desc@1057_001';name='combatant_trial@name@1057_001'
        c=player.Context({key:'説明',name:'ユキ'}, {name:'Yuki is a Combatant who uses <color_skyblue>[Prepare to Subdue]</> cards.',
              'card@name@skill1':'Prepare to Subdue'},names={'1057':'Yuki'})
        model=player.model(self.delta(self.change(key,kind='new')),c)
        self.assertIn('nội dung về Yuki',model['text']);self.assertIn('Prepare to Subdue',model['text'])
        self.assertEqual(model['changes'][0]['player_context']['status'],'source_description_subject')

    def test_internal_category_cannot_turn_unlock_into_voice(self):
        change=self.change('unlock_condition_state@noti_desc@account_level_20');change['group']='Tactical & Combat Voice (Ưu tiên 3)'
        text=player.model(self.delta(change))['text']
        self.assertIn('Điều kiện mở khóa tính năng',text);self.assertNotIn('Thoại nhân vật',text);self.assertNotIn('Tactical',text)

    def test_flat_ui_keys_have_player_locations_without_numeric_guesses(self):
        for identity,label in [('gacha_btn_retry','Chiêu mộ'),('shop_skin_info_popup_title','Cửa hàng'),
                               ('ui@story_exit_desc','Giao diện'),('mail@text@cash_shop','Hòm thư')]:
            text=player.model(self.delta(self.change(identity)))['text']
            self.assertIn(label,text)
            self.assertNotIn('chưa xác định vị trí',text)

    def test_exact_script_reference_classifies_dialogue_without_guessing_map(self):
        key='stys0126a@ent_50';c=player.Context({key:'文'})
        c.script('enact/script_name.sract',[{'yuna':key}],{key})
        row=player.model(self.delta(self.change(key)),c)['changes'][0]
        self.assertEqual(row['content_type'],'thoại, lời dẫn và lựa chọn')
        self.assertEqual(row['player_context']['status'],'unresolved')
        self.assertIn('chưa xác định bản đồ',row['player_context']['entity'])

    def test_markup_is_sanitized_for_display_without_changing_payload(self):
        after='Gây <cc>#damage#</> sát thương<br>với $効果$';change=self.change(after=after)
        model=player.model(self.delta(change),self.context())
        self.assertEqual(change['after'],after);self.assertEqual(model['changes'][0]['after'],after)
        self.assertNotIn('<cc>',model['changes'][0]['after_display']);self.assertNotIn('$効果$',model['changes'][0]['after_display'])
        self.assertIn('〔giá trị〕',model['changes'][0]['after_display'])

    def test_duplicate_ids_fail_instead_of_inflating_counts(self):
        with self.assertRaises(ValueError):player.model(self.delta(self.change(),self.change()),self.context())

    def test_large_summary_keeps_full_details_and_exact_counts(self):
        c=player.Context();changes=[]
        for i in range(100):
            key='id'+str(i);c.index[key]=[{'section':player.SECTIONS[i%len(player.SECTIONS)],'entity':'Tên '+str(i)+' rất dài '*15,
                'status':'source_reference','evidence':[]}];changes.append(self.change(key,kind='new'))
        model=player.model(self.delta(*changes),c,limit=3000)
        self.assertLessEqual(len(model['text']),3000);self.assertEqual(len(model['changes']),100)
        self.assertEqual(sum(len(g['ids']) for g in model['groups']),100);self.assertEqual(model['counts']['new'],100)
        self.assertIn('nhóm còn lại',model['text'])
        for section in player.SECTIONS:self.assertIn(section+':',model['text'])

    def test_no_change_message(self):
        self.assertEqual(player.model(self.delta())['text'],'Không có thay đổi bản dịch so với bản đã phát hành 1.5.3.')

    def test_new_edited_removed_are_separate_and_not_gameplay_claims(self):
        text=player.model(self.delta(self.change('a','new'),self.change('b','edited'),self.change('c','removed')))['text']
        self.assertIn('Thêm tiếng Việt: 1 dòng; sửa bản dịch: 1 dòng; ngừng áp dụng: 1 dòng',text)
        self.assertNotIn('buff',text);self.assertNotIn('nerf',text)

    def test_frozen_details_must_match_preview_hash_and_notice(self):
        with tempfile.TemporaryDirectory() as temp:
            out=Path(temp);details=player.model(self.delta(self.change()),self.context())
            path=out/'PLAYER_CHANGELOG.json';path.write_text(json.dumps(details,ensure_ascii=False),encoding='utf-8')
            record={'directory':temp,'player_changelog_sha256':sync.digest(path),'automatic_notice':details['text'],'unpublished_count':1}
            self.assertEqual(sync.load_player_details(record),details)
            path.write_text('{}',encoding='utf-8')
            with self.assertRaises(RuntimeError):sync.load_player_details(record)

    def test_frozen_details_wrong_count_rejected_even_with_valid_hash(self):
        with tempfile.TemporaryDirectory() as temp:
            out=Path(temp);details=player.model(self.delta(self.change()),self.context());path=out/'PLAYER_CHANGELOG.json'
            path.write_text(json.dumps(details),encoding='utf-8')
            record={'directory':temp,'player_changelog_sha256':sync.digest(path),'automatic_notice':details['text'],'unpublished_count':99}
            with self.assertRaises(RuntimeError):sync.load_player_details(record)

    def test_private_player_details_tamper_rejected_before_network(self):
        with tempfile.TemporaryDirectory() as temp:
            out=Path(temp)
            names=['CZN_Android_v1.5.2.cznpatch','channel.json','HUONG_DAN_ANDROID.txt','SHA256SUMS.txt']
            for name in names:(out/name).write_bytes(b'fixture')
            for name in ['TRANSLATION_SNAPSHOT.json','UNPUBLISHED_CHANGES.json','PLAYER_CHANGELOG.json']:(out/name).write_text('{}',encoding='utf-8')
            preview={'directory':temp,'version':'1.5.2','asset_hashes':{n:sync.digest(out/n) for n in names},
                 'translation_snapshot_sha256':sync.digest(out/'TRANSLATION_SNAPSHOT.json'),
                 'unpublished_changes_sha256':sync.digest(out/'UNPUBLISHED_CHANGES.json'),
                 'player_changelog_sha256':sync.digest(out/'PLAYER_CHANGELOG.json')}
            (out/'SYNC_PREVIEW.json').write_text(json.dumps(preview),encoding='utf-8')
            (out/'PLAYER_CHANGELOG.json').write_text('{"changed":true}',encoding='utf-8')
            with patch.object(sync,'check_updates') as check,patch.object(sync,'credentials') as credentials:
                with self.assertRaises(RuntimeError):sync.publish(preview)
                check.assert_not_called();credentials.assert_not_called()

    def test_check_after_prepare_invalidates_frozen_preview(self):
        import tkinter as tk
        from tkinter import ttk
        from types import SimpleNamespace
        from unittest.mock import Mock
        import time
        import android_sync_ui as ui
        root=tk.Tk();root.withdraw()
        try:
            def hidden_window(parent):
                win=tk.Toplevel(parent);win.withdraw();real_after=win.after
                win.after=lambda ms,*args:None if ms==200 else real_after(ms,*args)
                return win
            api=SimpleNamespace(Toplevel=hidden_window,Text=tk.Text,StringVar=tk.StringVar)
            with tempfile.TemporaryDirectory() as temp:
                app=SimpleNamespace(root=root,tk=api,ttk=ttk,home=Path(temp),busy=False,buttons=[],
                    game_var=tk.StringVar(value=temp),filedialog=Mock(),messagebox=Mock())
                details=player.model(self.delta(self.change()),self.context())
                record={'version':'1.5.5','notice':{'title':'Tiêu đề','body':details['text']},
                    'automatic_notice':details['text'],'unpublished_count':1,'app':{'app_size':70000000},'evidence':{'bundle_bytes':10,'bundle_sha256':'fixture'}}
                channel={'patch_version':'1.5.4','patch_code':10504,'app_version':'1.5.2','app_code':10502}
                with patch.object(ui,'Installer'),patch.object(ui,'prepare',return_value=record), \
                     patch.object(ui,'load_player_details',return_value=details),patch.object(ui,'check_updates',return_value=channel), \
                     patch.object(ui,'notice_preview_data',return_value=player.model(self.delta())):
                    win=ui.show_android_sync(app)
                    def widgets(widget):
                        for child in widget.winfo_children():
                            yield child;yield from widgets(child)
                    buttons={w.cget('text'):w for w in widgets(win) if isinstance(w,ttk.Button)}
                    def finish():
                        deadline=time.monotonic()+2
                        while app.busy and time.monotonic()<deadline:root.update();time.sleep(.01)
                        self.assertFalse(app.busy)
                    buttons['Dựng & kiểm tra gói'].invoke();finish()
                    self.assertEqual(str(buttons['Phát hành lên GitHub'].cget('state')),'normal')
                    buttons['Kiểm tra cập nhật'].invoke();finish()
                    self.assertEqual(str(buttons['Phát hành lên GitHub'].cget('state')),'disabled')
                    self.assertEqual(str(buttons['Xem chi tiết / tìm nội dung'].cget('state')),'disabled')
        finally:root.destroy()

    def test_detail_window_searches_names_cards_and_before_after(self):
        try:
            import tkinter as tk
            from tkinter import ttk
            from types import SimpleNamespace
            from android_sync_ui import show_player_details
            root=tk.Tk();root.withdraw()
        except Exception as error:
            self.skipTest('Tk unavailable: '+str(error))
        try:
            def hidden_window(parent):
                win=tk.Toplevel(parent);win.withdraw();return win
            api=SimpleNamespace(Toplevel=hidden_window,Text=tk.Text,StringVar=tk.StringVar)
            details=player.model(self.delta(self.change()),self.context())
            show_player_details(root,details,api,ttk);root.update_idletasks()
            def all_widgets(widget):
                for child in widget.winfo_children():
                    yield child;yield from all_widgets(child)
            widgets=list(all_widgets(root));tree=next(x for x in widgets if isinstance(x,ttk.Treeview));entry=next(x for x in widgets if isinstance(x,ttk.Entry))
            self.assertEqual(len(tree.get_children()),1)
            entry.insert(0,'Heart Breaker');root.update_idletasks();self.assertEqual(len(tree.get_children()),1)
            entry.delete(0,'end');entry.insert(0,'Không tìm thấy');root.update_idletasks();self.assertEqual(len(tree.get_children()),0)
        finally:
            root.destroy()


if __name__=='__main__':unittest.main()
