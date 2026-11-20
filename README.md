# LocApp

App para iPhone (SwiftUI + MapKit) onde você arrasta um pin no mapa, toca em **Aplicar localização** e aquele ponto passa a ser a localização ativa do app. Também exporta o ponto como `.gpx` para simular a localização do iPhone inteiro pelo Xcode.

## O que o app faz

- Mapa com um pin que você **arrasta**, ou **toca no mapa** para posicionar.
- Busca por endereço ou lugar.
- Coordenadas exatas do pin, com botão de copiar.
- **Aplicar localização**: fixa o ponto como localização ativa (fica salvo entre aberturas).
- **GPS real**: volta a usar a localização verdadeira.
- **Exportar .gpx**: gera o arquivo do ponto e abre o compartilhar (AirDrop para o Mac, Arquivos etc.).
- Interface minimalista em tons neutros, com modo claro e escuro.

## Limitação importante do iOS

O iOS **não deixa um app comum mudar a localização do sistema** para os outros apps (Maps, Instagram, Uber...). Isso só é possível com jailbreak, e este projeto não vai por esse caminho.

Na prática:

1. **Dentro do LocApp** (e de qualquer código que use o `LocationService`), a localização aplicada vale de verdade.
2. **Para o iPhone inteiro**, durante desenvolvimento: use o `.gpx` exportado no Xcode (abaixo). Enquanto o Xcode estiver depurando um app no iPhone, a localização do aparelho inteiro fica naquele ponto.

## Instalar a .ipa

A `.ipa` gerada pelo GitHub Actions **não é assinada** (assinar exige certificado da Apple). Para instalar:

1. Baixe a `.ipa` em *Releases* (ou em *Actions → último build → Artifacts*).
2. Instale com **Sideloadly** (Windows/Mac) ou **AltStore**, que assinam com o seu Apple ID.
3. No iPhone: *Ajustes → Geral → VPN e Gerenciamento de Dispositivo* → confie no seu perfil.
4. No iOS 16+: ative *Ajustes → Privacidade e Segurança → Modo de Desenvolvedor*.

Com Apple ID gratuito o app expira em 7 dias e precisa ser reinstalado.

## Rodar pelo Xcode (alternativa)

1. Abra `LocApp.xcodeproj` no Xcode 16 ou mais novo.
2. Em *Signing & Capabilities*, escolha seu Team e, se precisar, troque o Bundle ID (`com.lotte.LocApp`).
3. Escolha o iPhone (ou um Simulator) e rode com ⌘R. Requer iOS 17+.

## Simular a localização do iPhone inteiro com .gpx

1. No LocApp, posicione o pin e toque em **Exportar .gpx**. Mande o arquivo para o Mac (AirDrop).
2. Arraste o `.gpx` para dentro do projeto no Xcode (qualquer projeto seu).
3. Rode o app no iPhone pelo Xcode.
4. Na barra de debug, clique no ícone de localização (*Simulate Location*) e escolha o `.gpx`. Também dá para usar *Debug → Simulate Location*.

O projeto já traz um exemplo em `LocApp/GPX/Paulista.gpx`.

## Usar a localização simulada no seu código

Leia a localização sempre pelo serviço, nunca direto do `CLLocationManager`:

```swift
let loc = LocationService.shared.currentLocation   // simulada se aplicada, senão GPS real

// ou observando mudanças (Combine)
LocationService.shared.$activeLocation
    .compactMap { $0 }
    .sink { print($0.coordinate) }
```

## Estrutura

```
LocApp/
├── LocAppApp.swift        // entrada do app
├── ContentView.swift      // mapa, pin arrastável, busca, painel
├── LocationService.swift  // GPS real + localização simulada
├── GPXExporter.swift      // gera o .gpx
├── GPX/Paulista.gpx       // exemplo para o Xcode
└── Assets.xcassets
.github/workflows/build-ipa.yml  // compila a .ipa no GitHub Actions
```
