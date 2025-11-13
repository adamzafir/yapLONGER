import Foundation
import SwiftUI
import Combine

struct ScriptItem: Identifiable {
    var id: UUID
    var title: String
    var scriptText: String
}

class Screen2ViewModel: ObservableObject {
    @Published var scriptItems: [ScriptItem] = [
        ScriptItem(
            id: UUID(),
            title: "The Impact of Social Media on Society",
            scriptText: """
Social media has profoundly transformed the way people communicate and interact with one another. Over the past decade, platforms like Facebook, Twitter, and Instagram have enabled instant sharing of information, connecting people across the globe. On the positive side, social media allows for real-time communication, collaboration, and access to educational resources. Social movements have gained traction through social media campaigns, giving a voice to marginalized communities. However, there are also significant drawbacks. The constant exposure to curated content can lead to unrealistic expectations, mental health issues, and the spread of misinformation. Social media algorithms often prioritize engagement over accuracy, amplifying sensationalized content. In addition, the addictive nature of these platforms can disrupt daily routines and productivity. It is essential for individuals to practice mindful consumption, critically evaluate content, and maintain a healthy balance between online and offline interactions to mitigate the negative effects of social media while still leveraging its potential for connectivity and learning.
"""
        ),
        ScriptItem(
            id: UUID(),
            title: "Climate Change and Its Global Consequences",
            scriptText: """
Climate change is one of the most pressing challenges facing humanity today. Rising global temperatures, melting glaciers, and shifting weather patterns are evidence of the ongoing impact of human activities, particularly the emission of greenhouse gases. The consequences of climate change are far-reaching: more frequent and severe natural disasters, rising sea levels, and disruptions to food and water supply. Ecosystems are being altered, threatening biodiversity and the survival of numerous species. Vulnerable populations in developing countries often bear the brunt of these effects, exacerbating social and economic inequalities. Combating climate change requires coordinated global action, including transitioning to renewable energy, improving energy efficiency, and implementing sustainable agricultural and industrial practices. Public awareness and policy initiatives are crucial to mitigating the worst outcomes. While the challenge is enormous, proactive measures taken today can help secure a healthier, more sustainable planet for future generations.
"""
        ),
        ScriptItem(
            id: UUID(),
            title: "The Benefits and Challenges of Remote Learning",
            scriptText: """
Remote learning has become increasingly prevalent, especially in response to the global COVID-19 pandemic. The primary advantage of remote learning is flexibility; students can access educational materials from anywhere, often at their own pace. It can also broaden access to quality education for individuals in remote or underserved areas. Technology-enabled learning provides opportunities for personalized instruction, interactive resources, and collaborative tools. However, remote learning also presents significant challenges. The lack of face-to-face interaction can affect motivation, engagement, and social development. Technical issues, limited access to reliable internet, and insufficient digital literacy further exacerbate the difficulties for some students. Additionally, teachers must adapt their pedagogical strategies to maintain effectiveness in a virtual environment. Balancing these benefits and challenges is key to optimizing remote education. Hybrid models that combine in-person and online instruction may offer the best of both worlds, ensuring accessibility without compromising the social and academic experience.
"""
        ),
        ScriptItem(
            id: UUID(),
            title: "The Role of Artificial Intelligence in Modern Life",
            scriptText: """
Artificial intelligence (AI) is increasingly shaping the way humans interact with technology, work, and daily life. From voice-activated assistants to recommendation algorithms, AI systems have become integral to personal and professional activities. In healthcare, AI aids in diagnostics, personalized treatment plans, and drug discovery. In business, it improves efficiency, automates repetitive tasks, and provides data-driven insights. However, the rise of AI also brings ethical and societal concerns. Issues such as job displacement, privacy violations, biased algorithms, and the potential for autonomous decision-making raise important questions about regulation and accountability. It is crucial for policymakers, developers, and society at large to address these challenges proactively. Emphasizing transparency, ethical design, and human oversight can help ensure that AI technologies augment human capabilities while minimizing harm, creating a future where AI serves as a tool for progress rather than a source of unintended consequences.
"""
        ),
        ScriptItem(
            id: UUID(),
            title: "The Importance of Mental Health Awareness",
            scriptText: """
Mental health is an essential component of overall well-being, yet it has often been overlooked or stigmatized. Awareness and understanding of mental health issues such as anxiety, depression, and stress are critical for promoting healthy communities. Early recognition and intervention can prevent conditions from worsening and improve quality of life. Mental health challenges affect individuals of all ages, backgrounds, and professions, highlighting the need for accessible support systems and resources. Society plays a crucial role in reducing stigma, encouraging open dialogue, and fostering supportive environments. Employers, educators, and healthcare providers must prioritize mental wellness initiatives and create spaces where individuals feel safe seeking help. By normalizing conversations around mental health and providing effective resources, we can promote resilience, empathy, and a more compassionate society that recognizes mental well-being as equally important as physical health.
"""
        )
    ]
}
