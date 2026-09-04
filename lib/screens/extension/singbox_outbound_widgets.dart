// Widget editors for SingboxOutboundOptions used by the add/edit server UI.
import 'package:flutter/material.dart';

import 'package:karing/app/utils/singbox_outbound.dart';
import 'package:karing/i18n/strings.g.dart';
import 'package:karing/screens/group_item_creator.dart';
import 'package:karing/screens/group_item_options.dart';



extension SingboxOutboundOptionsWidgets on SingboxOutboundOptions {
  List<GroupItem> getWidgetOptions(BuildContext context, SetStateCallback? setstate) {
    final tcontext = Translations.of(context);
    final options = <GroupItemOptions>[];

    void addTextField(String name, String? text, bool obscure,
        void Function(String) onChanged) {
      options.add(GroupItemOptions(
        textFormFieldOptions: GroupItemTextFieldOptions(
          name: name,
          text: text ?? "",
          obscureText: obscure,
          textWidthPercent: 0.6,
          onChanged: onChanged,
        ),
      ));
    }

    switch (type) {
      case SingboxOutboundType.shadowsocks:
        addTextField("method", shadowsocks?.method, false, (v) {
          shadowsocks?.method = v;
          setstate?.call();
        });
        addTextField("password", shadowsocks?.password, true, (v) {
          shadowsocks?.password = v;
          setstate?.call();
        });
        break;
      case SingboxOutboundType.shadowsocksr:
        addTextField("protocol", shadowsocksr?.protocol, false, (v) {
          shadowsocksr?.protocol = v;
          setstate?.call();
        });
        addTextField("method", shadowsocksr?.method, false, (v) {
          shadowsocksr?.method = v;
          setstate?.call();
        });
        addTextField("password", shadowsocksr?.password, true, (v) {
          shadowsocksr?.password = v;
          setstate?.call();
        });
        break;
      case SingboxOutboundType.shadowtls:
        addTextField("password", shadowtls?.password, true, (v) {
          shadowtls?.password = v;
          setstate?.call();
        });
        break;
      case SingboxOutboundType.vmess:
        addTextField("uuid", vmess?.uuid, false, (v) {
          vmess?.uuid = v;
          setstate?.call();
        });
        addTextField("security", vmess?.security ?? "auto", false, (v) {
          vmess?.security = v;
          setstate?.call();
        });
        break;
      case SingboxOutboundType.vless:
        addTextField("uuid", vless?.uuid, false, (v) {
          vless?.uuid = v;
          setstate?.call();
        });
        addTextField("flow", vless?.flow, false, (v) {
          vless?.flow = v;
          setstate?.call();
        });
        break;
      case SingboxOutboundType.trojan:
        addTextField("password", trojan?.password, true, (v) {
          trojan?.password = v;
          setstate?.call();
        });
        break;
      case SingboxOutboundType.socks:
        addTextField("username", socks?.username, false, (v) {
          socks?.username = v;
          setstate?.call();
        });
        addTextField("password", socks?.password, true, (v) {
          socks?.password = v;
          setstate?.call();
        });
        break;
      case SingboxOutboundType.http:
        addTextField("username", http?.username, false, (v) {
          http?.username = v;
          setstate?.call();
        });
        addTextField("password", http?.password, true, (v) {
          http?.password = v;
          setstate?.call();
        });
        break;
      case SingboxOutboundType.hysteria:
        addTextField(tcontext.meta.password, hysteria?.auth_str, true, (v) {
          hysteria?.auth_str = v;
          setstate?.call();
        });
        break;
      case SingboxOutboundType.hysteria2:
        addTextField(tcontext.meta.password, hysteria2?.password, true, (v) {
          hysteria2?.password = v;
          setstate?.call();
        });
        break;
      case SingboxOutboundType.wireguard:
        addTextField("private_key", wg?.private_key, true, (v) {
          wg?.private_key = v;
          setstate?.call();
        });
        addTextField("peer_public_key", wg?.peer_public_key, false, (v) {
          wg?.peer_public_key = v;
          setstate?.call();
        });
        break;
      case SingboxOutboundType.tuic:
        addTextField("uuid", tuic?.uuid, false, (v) {
          tuic?.uuid = v;
          setstate?.call();
        });
        addTextField(tcontext.meta.password, tuic?.password, true, (v) {
          tuic?.password = v;
          setstate?.call();
        });
        break;
      case SingboxOutboundType.ssh:
        addTextField("user", ssh?.user, false, (v) {
          ssh?.user = v;
          setstate?.call();
        });
        addTextField("private_key", ssh?.private_key, true, (v) {
          ssh?.private_key = v;
          setstate?.call();
        });
        break;
      case SingboxOutboundType.anytls:
        addTextField(tcontext.meta.password, anytls?.password, true, (v) {
          anytls?.password = v;
          setstate?.call();
        });
        break;
      case SingboxOutboundType.mieru:
        addTextField(tcontext.meta.password, mieru?.password, true, (v) {
          mieru?.password = v;
          setstate?.call();
        });
        break;
      case SingboxOutboundType.naive:
        addTextField("username", naive?.username, false, (v) {
          naive?.username = v;
          setstate?.call();
        });
        addTextField(tcontext.meta.password, naive?.password, true, (v) {
          naive?.password = v;
          setstate?.call();
        });
        break;
      default:
        break;
    }

    return [GroupItem(options: options)];
  }
}
